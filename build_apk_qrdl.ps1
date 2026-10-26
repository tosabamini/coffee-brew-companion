# Build a small release APK (arm64 only) and share it with QRDL.
# Progress lines are shown on screen; the full verbose log goes to build_apk.log.
$ErrorActionPreference = "Continue"
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$app  = Join-Path $root "coffee_brew_smartphoneapp"
$log  = Join-Path $root "build_apk.log"
$out  = Join-Path $app "build\app\outputs\flutter-apk"
Set-Location $app
Write-Host "Building release APK... (first time can take 10+ minutes)" -ForegroundColor Cyan
Write-Host "Full log: $log"
$w = New-Object IO.StreamWriter($log, $false, [Text.Encoding]::UTF8)
$w.AutoFlush = $true
$start = Get-Date
& flutter build apk --release --split-per-abi --target-platform android-arm64 -v 2>&1 | ForEach-Object {
    $line = "$_"
    $w.WriteLine($line)
    if ($line -match "> Task :|Download |BUILD |FAILURE|What went wrong|Exception|error:|Waiting|lock|Built build") {
        $t = [int]((Get-Date) - $start).TotalSeconds
        Write-Host ("[{0,4}s] {1}" -f $t, $line.Trim())
    }
}
$code = $LASTEXITCODE
$w.Close()
if ($code -ne 0) { Write-Host "Build FAILED (exit $code). See $log" -ForegroundColor Red; exit 1 }
$src = Join-Path $out "app-arm64-v8a-release.apk"
$dst = Join-Path $out "CoffeeBrewCompanion-arm64.apk"
Copy-Item -LiteralPath $src -Destination $dst -Force
$mb = "{0:N1}" -f ((Get-Item $dst).Length / 1MB)
Write-Host "Done: $dst ($mb MB)" -ForegroundColor Green
& powershell -NoProfile -ExecutionPolicy Bypass -File "C:\Users\issas\Desktop\QRDL\qrdl.ps1" $dst
