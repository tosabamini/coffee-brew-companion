# Allow the Coffee Lab receiver (TCP 47130 / UDP 47131) through Windows Firewall on all network types.
# Also removes "Block" rules for python.exe that Windows creates when its first-time prompt was cancelled.
$removed = 0
Get-NetFirewallRule -Direction Inbound -Action Block -ErrorAction SilentlyContinue | ForEach-Object {
    $prog = ($_ | Get-NetFirewallApplicationFilter).Program
    if ($prog -match '\\pythonw?[0-9.]*\.exe$') {
        Write-Host "Removed block rule: $($_.DisplayName)  ($prog)"
        Remove-NetFirewallRule -Name $_.Name
        $removed++
    }
}
foreach ($r in @(@{n='Coffee Lab (TCP 47130)'; p='TCP'; port=47130}, @{n='Coffee Lab (UDP 47131)'; p='UDP'; port=47131})) {
    Remove-NetFirewallRule -DisplayName $r.n -ErrorAction SilentlyContinue
    New-NetFirewallRule -DisplayName $r.n -Direction Inbound -Protocol $r.p -LocalPort $r.port -Action Allow -Profile Any | Out-Null
    Write-Host "Allowed: $($r.n)"
}
Write-Host ""
Write-Host "Done. (python block rules removed: $removed)  Restart the receiver server and try again." -ForegroundColor Green
