# Build the Coffee Lab app (camera / light) as a small release APK and share it with QRDL.
$ErrorActionPreference = "Continue"
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$app  = Join-Path $root "coffee_lab_app"
$log  = Join-Path $root "build_lab_app.log"
$out  = Join-Path $app "build\app\outputs\flutter-apk"
Set-Location $app
$w = New-Object IO.StreamWriter($log, $false, [Text.Encoding]::UTF8)
$w.AutoFlush = $true
function Run($title, [scriptblock]$cmd) {
    Write-Host $title -ForegroundColor Cyan
    $start = Get-Date
    & $cmd 2>&1 | ForEach-Object {
        $line = "$_"
        $w.WriteLine($line)
        if ($line -match "> Task :|Download |BUILD |FAILURE|What went wrong|Exception|error:|Error:|Waiting|lock|Built build|Wrote |Got dependencies|Changed ") {
            $t = [int]((Get-Date) - $start).TotalSeconds
            Write-Host ("[{0,4}s] {1}" -f $t, $line.Trim())
        }
    }
    return $LASTEXITCODE
}
if (-not ((Test-Path "android\app\build.gradle.kts") -or (Test-Path "android\app\build.gradle"))) {
    $c = Run "First time: creating Android project files (existing files are kept)..." { flutter create --platforms android --org com.coffeelab --project-name coffee_lab_app . }
    if ($c -ne 0) { $w.Close(); Write-Host "flutter create FAILED. See $log" -ForegroundColor Red; exit 1 }
}
$c = Run "Getting packages..." { flutter pub get }
if ($c -ne 0) { $w.Close(); Write-Host "flutter pub get FAILED. See $log" -ForegroundColor Red; exit 1 }
$c = Run "Building release APK... (first time can take 10+ minutes)  Log: $log" { flutter build apk --release --split-per-abi --target-platform android-arm64 -v }
$w.Close()
if ($c -ne 0) { Write-Host "Build FAILED (exit $c). See $log" -ForegroundColor Red; exit 1 }
$src = Join-Path $out "app-arm64-v8a-release.apk"
$dst = Join-Path $out "CoffeeLab-arm64.apk"
Copy-Item -LiteralPath $src -Destination $dst -Force
$mb = "{0:N1}" -f ((Get-Item $dst).Length / 1MB)
Write-Host "Done: $dst ($mb MB)" -ForegroundColor Green
& powershell -NoProfile -ExecutionPolicy Bypass -File "C:\Users\issas\Desktop\QRDL\qrdl.ps1" $dst
