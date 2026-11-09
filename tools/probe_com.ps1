param([string]$Port = 'COM10')

$serial = [System.IO.Ports.SerialPort]::new($Port, 115200)
$serial.ReadTimeout = 1000
try {
    $serial.Open()
    Write-Host "Opened $Port successfully."
    
    # Reset ESP32 by pulsing DTR/RTS
    $serial.DtrEnable = $false
    $serial.RtsEnable = $true
    Start-Sleep -Milliseconds 200
    $serial.RtsEnable = $false
    Start-Sleep -Milliseconds 200
    
    Write-Host "Listening to boot logs..."
    $timeout = [DateTime]::UtcNow.AddSeconds(6)
    while ([DateTime]::UtcNow -lt $timeout) {
        try {
            $line = $serial.ReadLine().Trim()
            if ($line) {
                Write-Host "SERIAL >> $line"
            }
        } catch [TimeoutException] {
            # continue
        }
    }
} catch {
    Write-Host "Error accessing ${Port}: $($_.Exception.Message)"
} finally {
    if ($serial.IsOpen) {
        $serial.Close()
    }
    $serial.Dispose()
}
