$dev = Get-PnpDevice | Where-Object { $_.FriendlyName -like "*COM10*" }
if ($dev) {
    try {
        Disable-PnpDevice -InstanceId $dev.InstanceId -Confirm:$false
        Start-Sleep -Seconds 1
        Enable-PnpDevice -InstanceId $dev.InstanceId -Confirm:$false
        Write-Host "Reset PnP device successfully!"
    } catch {
        Write-Host "Error: $($_.Exception.Message)"
    }
}
