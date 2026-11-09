param([string]$Port = 'COM10')
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$local = Get-Content -Raw -LiteralPath (Join-Path $root '.work/campus-local.json') | ConvertFrom-Json
$headers = @{ Authorization = "Bearer $($local.deviceToken)" }
$base = 'http://localhost:8081/api/v1'

function Invoke-Device($path, $body) {
    if ($null -eq $body) {
        return (Invoke-RestMethod -Uri "$base$path" -Headers $headers -TimeoutSec 4).data
    }
    $requestHeaders = $headers.Clone()
    $requestHeaders['Idempotency-Key'] = [guid]::NewGuid().ToString()
    return (Invoke-RestMethod -Uri "$base$path" -Headers $requestHeaders -Method Post -ContentType 'application/json' -Body ($body | ConvertTo-Json -Depth 5 -Compress) -TimeoutSec 4).data
}

Write-Host "Connecting to $Port (115200 baud)..." -ForegroundColor Yellow
$serial = [IO.Ports.SerialPort]::new($Port, 115200)
$serial.ReadTimeout = 500
$serial.DtrEnable = $false
$serial.RtsEnable = $false

try {
    $serial.Open()
    Write-Host "==========================================" -ForegroundColor Green
    Write-Host " RFID USB BRIDGE CONNECTED ON $Port" -ForegroundColor Green
    Write-Host " Ready to receive card taps!" -ForegroundColor Green
    Write-Host "==========================================" -ForegroundColor Green
    
    $nextPoll = [DateTime]::MinValue
    $lastHeartbeat = [DateTime]::UtcNow
    
    while ($true) {
        try {
            if ([DateTime]::UtcNow -ge $nextPoll) {
                $nextPoll = [DateTime]::UtcNow.AddSeconds(2)
                $config = Invoke-Device '/device/config' $null
                if (!$config.acknowledged) {
                    $null = Invoke-Device '/device/config-ack' @{
                        deviceId = $config.deviceId; configVersion = $config.configVersion
                    }
                }
            }
            
            try { 
                $line = $serial.ReadLine().Trim() 
            } catch [TimeoutException] { 
                continue 
            }
            
            if ($line) {
                Write-Host "[SERIAL] $line" -ForegroundColor Gray
            }
            
            if ($line -notmatch '^UID=([0-9A-F]{8}|[0-9A-F]{14}|[0-9A-F]{20})$') { 
                continue 
            }
            
            $uid = $Matches[1]
            Write-Host "`n>>> [THẺ RFID ĐƯỢC CHẠM] UID: $uid" -ForegroundColor Green
            
            # 1. Luôn gửi ngay lập tức tới /device/raw-tap cho màn hình đăng ký Admin Wizard
            try { 
                $tapRes = Invoke-Device '/device/raw-tap' @{ uid = $uid }
                Write-Host "    -> Đã gửi đến /device/raw-tap thành công (UID=$uid)" -ForegroundColor Cyan
            } catch {
                Write-Warning "    -> Không gửi được tới /device/raw-tap: $_"
            }
            
            # 2. Nếu đang có ngữ cảnh bãi xe hoặc căng tin, hoàn tất xác thực sự kiện
            $config = Invoke-Device '/device/config' $null
            if (!$config.context -or !$config.acknowledged) {
                Write-Host "    -> Lưu ý: Chưa mở lượt gửi xe/căng tin (đang ở chế độ chờ hoặc đăng ký)." -ForegroundColor Yellow
                continue
            }
            
            $context = @{
                deviceId = $config.deviceId; configVersion = $config.configVersion
                contextId = $config.context.id
            }
            $challenge = Invoke-Device '/device/challenges' $context
            $null = Invoke-Device '/device-events' ($context + @{
                schemaVersion = 1; eventId = [guid]::NewGuid().ToString()
                deviceRole = $config.role; challengeId = $challenge.challengeId
                nonce = $challenge.nonce; occurredAt = [DateTime]::UtcNow.ToString('o')
                credential = @{ type = 'RFID_UID'; uid = $uid }
            })
            Write-Host "    -> Xác thực sự kiện $($config.context.purpose) thành công!" -ForegroundColor Green
            
        } catch {
            $response = $_.Exception.Response
            if ($response) { 
                Write-Warning "Device API trả về mã $([int]$response.StatusCode). Kiểm tra cấu hình và thẻ." 
            } else { 
                Write-Warning "Không kết nối được Device API hoặc cổng COM: $($_.Exception.Message)"
                Start-Sleep -Seconds 2 
            }
        }
    }
} finally {
    if ($serial.IsOpen) {
        $serial.Close()
    }
    $serial.Dispose()
    Write-Host "Đã đóng cổng $Port." -ForegroundColor Yellow
}
