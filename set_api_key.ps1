# set_api_key.ps1 - Claude API キーを入れ替える（set_api_key.bat から起動）
#   1. キーを貼り付けてもらう（画面には表示しない）
#   2. Anthropic API に小さな問い合わせをして、キーが使えるか確かめる（使えなければ書き込まない）
#   3. coffee_brew_smartphoneapp\lib\config\api_config.dart の claudeApiKey の行だけを書き換える
#   4. 続けて APK をビルドして QRDL で配るか聞く
# キーは画面・ログ・Git に出さない（このスクリプトはキーをどこにも記録しない）。
# Windows PowerShell 5.1 で動作（追加インストール不要）

$ErrorActionPreference = 'Continue'
try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch {}
try { $Host.UI.RawUI.WindowTitle = 'Claude API キーの入れ替え' } catch {}

$Root     = Split-Path -Parent $MyInvocation.MyCommand.Path
$CfgRel   = 'coffee_brew_smartphoneapp/lib/config/api_config.dart'
$Cfg      = Join-Path $Root ($CfgRel -replace '/', '\')
$Example  = "$Cfg.example"
$BuildPs1 = Join-Path $Root 'build_apk_qrdl.ps1'
$KeyLine  = [regex]"(?m)^([ \t]*static[ \t]+const[ \t]+String[ \t]+claudeApiKey[ \t]*=[ \t]*)'([^'\r\n]*)'([ \t]*;)"
$Utf8     = New-Object Text.UTF8Encoding($false)

function Say([string]$t, [string]$c = 'Gray') { Write-Host $t -ForegroundColor $c }

# エラー文などにキーらしき文字列が混ざっていても表示しない
function Hide-Key([string]$s) { return [regex]::Replace("$s", 'sk-ant-[A-Za-z0-9_\-]+', '（キー）') }

function Ask-YesNo([string]$q) {
    while ($true) {
        $a = (Read-Host "$q (Y/N)").Trim().ToUpper()
        if ($a -eq 'Y') { return $true }
        if ($a -eq 'N') { return $false }
    }
}

# ---------- 設定ファイルを読む ----------
function Read-Cfg {
    $bytes = [IO.File]::ReadAllBytes($Cfg)
    $bom = ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)
    $text = $Utf8.GetString($bytes)
    if ($bom) { $text = $text.Substring(1) }
    return @{ Text = $text; Bom = $bom }
}

# ---------- Git に載らないことを確かめる ----------
function Test-NotInGit {
    if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
        # git コマンドがない場合は .gitignore の記述で確かめる
        $gi = Join-Path $Root '.gitignore'
        if ((Test-Path -LiteralPath $gi) -and ((Get-Content -LiteralPath $gi -Encoding UTF8) -contains $CfgRel)) { return $true }
        Say "api_config.dart が .gitignore に入っていることを確かめられませんでした。" Red
        return $false
    }
    & git -C $Root ls-files --error-unmatch -- $CfgRel 1>$null 2>$null
    if ($LASTEXITCODE -eq 0) {
        Say "api_config.dart が Git に登録されています。このまま書き込むとキーがコミットに入るため、中止します。" Red
        Say "  （git rm --cached $CfgRel で登録を外してから、もう一度実行してください）" Red
        return $false
    }
    & git -C $Root check-ignore -q -- $CfgRel 1>$null 2>$null
    if ($LASTEXITCODE -ne 0) {
        Say "api_config.dart が .gitignore の対象になっていません。キーがコミットに入るおそれがあるため、中止します。" Red
        return $false
    }
    return $true
}

# ---------- キーを受け取る（画面には何も出さない） ----------
function Read-Secret {
    $ss = New-Object Security.SecureString
    try {
        while ($true) {
            $k = [Console]::ReadKey($true)
            if ($k.Key -eq [ConsoleKey]::Enter) { if ($ss.Length -gt 0) { break } else { continue } }
            if ($k.Key -eq [ConsoleKey]::Backspace) { if ($ss.Length -gt 0) { $ss.RemoveAt($ss.Length - 1) }; continue }
            if ($k.Key -eq [ConsoleKey]::Escape) { $ss.Clear(); continue }
            if ([int]$k.KeyChar -ge 0x20) { $ss.AppendChar($k.KeyChar) }
        }
    } catch {
        # 画面からキーを1文字ずつ読めない環境では、伏せ字入力に切り替える
        $ss = Read-Host -AsSecureString 'キー'
    }
    Write-Host ''
    $p = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($ss)
    try { $plain = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($p) }
    finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($p); $ss.Dispose() }
    # 貼り付けに混ざった空白・改行・引用符を取り除く
    return ($plain -replace '\s', '').Trim("'", '"')
}

# ---------- キーが使えるか確かめる（Haiku に 1 トークンだけ問い合わせ。費用はごくわずか） ----------
function Test-ApiKey([string]$key, [string]$model) {
    Add-Type -AssemblyName System.Net.Http
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    $client = New-Object System.Net.Http.HttpClient
    $client.Timeout = [TimeSpan]::FromSeconds(30)
    try {
        $req = New-Object System.Net.Http.HttpRequestMessage([System.Net.Http.HttpMethod]::Post, 'https://api.anthropic.com/v1/messages')
        [void]$req.Headers.TryAddWithoutValidation('x-api-key', $key)
        [void]$req.Headers.TryAddWithoutValidation('anthropic-version', '2023-06-01')
        $body = '{"model":"' + $model + '","max_tokens":1,"messages":[{"role":"user","content":"ping"}]}'
        $req.Content = New-Object System.Net.Http.StringContent($body, [Text.Encoding]::UTF8, 'application/json')
        $res = $client.SendAsync($req).GetAwaiter().GetResult()
        $text = $res.Content.ReadAsStringAsync().GetAwaiter().GetResult()
        $type = ''; $msg = ''
        try { $j = $text | ConvertFrom-Json; $type = "$($j.error.type)"; $msg = "$($j.error.message)" } catch {}
        return @{ Status = [int]$res.StatusCode; Type = $type; Message = (Hide-Key $msg) }
    } catch {
        return @{ Status = 0; Type = ''; Message = (Hide-Key $_.Exception.GetBaseException().Message) }
    } finally {
        $client.Dispose()
    }
}

# ---------- 書き込む（claudeApiKey の行だけ） ----------
function Write-Key([string]$key) {
    $c = Read-Cfg
    $script:NewKey = $key
    $eval = [Text.RegularExpressions.MatchEvaluator] { param($m) $m.Groups[1].Value + "'" + $script:NewKey + "'" + $m.Groups[3].Value }
    $newText = $KeyLine.Replace($c.Text, $eval, 1)
    $script:NewKey = $null
    $tmp = "$Cfg.tmp-" + [guid]::NewGuid().ToString('N')
    try {
        $out = $Utf8.GetBytes($newText)
        if ($c.Bom) { $out = [byte[]](@(0xEF, 0xBB, 0xBF) + $out) }
        [IO.File]::WriteAllBytes($tmp, $out)
        Move-Item -LiteralPath $tmp -Destination $Cfg -Force -ErrorAction Stop
    } finally {
        if (Test-Path -LiteralPath $tmp) { Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue }
    }
    # 書けたか確かめる（中身は表示しない）
    $after = $KeyLine.Matches((Read-Cfg).Text)
    return ($after.Count -eq 1 -and $after[0].Groups[2].Value -eq $key)
}

# ================= ここから =================
Say ''
Say '=== Claude API キーの入れ替え（Coffee Brew Companion） ===' Cyan
Say "書き換えるファイル: $Cfg"
Say ''

if (-not (Test-Path -LiteralPath $Cfg)) {
    if (-not (Test-Path -LiteralPath $Example)) { Say "api_config.dart も、ひな形（api_config.dart.example）も見つかりません。" Red; exit 1 }
    if (-not (Test-NotInGit)) { exit 1 }
    Copy-Item -LiteralPath $Example -Destination $Cfg
    Say 'api_config.dart がなかったので、ひな形から作りました。' Yellow
}
if (-not (Test-NotInGit)) { exit 1 }

$cfgNow = Read-Cfg
$hits = $KeyLine.Matches($cfgNow.Text)
if ($hits.Count -ne 1) {
    Say "api_config.dart の中に claudeApiKey の行が $($hits.Count) か所あります（1か所のはず）。安全のため書き換えません。" Red
    exit 1
}
$model = 'claude-haiku-4-5'
$mm = [regex]::Match($cfgNow.Text, "visionModel[ \t]*=[ \t]*'([A-Za-z0-9._\-]+)'")
if ($mm.Success) { $model = $mm.Groups[1].Value }

$done = $false
$changed = $false
while (-not $done) {
    Say '新しいキーを貼り付けて Enter を押してください（Ctrl+V か右クリック）。入力した文字は表示されません。' White
    Say '  やめるときは何も入れずにウィンドウを閉じてください。' DarkGray
    $key = Read-Secret
    Say ("受け取りました（{0} 文字）" -f $key.Length) DarkGray

    if ($key -notmatch '^sk-ant-[A-Za-z0-9_\-]{20,}$') {
        Say 'キーの形ではありません（sk-ant- で始まる英数字のはず）。書き込みません。' Red
        $key = $null
        if (Ask-YesNo 'もう一度入力しますか？') { continue } else { break }
    }

    if ($hits[0].Groups[2].Value -eq $key) {
        Say '今のキーと同じです。書き換えは不要でした。' Yellow
        $done = $true
        break
    }

    Say "キーが使えるか確かめています（$model に 1 トークンだけ問い合わせ）..." DarkGray
    $r = Test-ApiKey $key $model
    $write = $false
    switch ($r.Status) {
        200 { Say 'キーは使えます。' Green; $write = $true }
        { $_ -eq 429 -or $_ -eq 529 } { Say 'キーは有効です（API が混雑中のため応答は返りませんでした）。' Green; $write = $true }
        401 { Say 'このキーは無効です（認証に失敗）。書き込みません。' Red }
        403 { Say "このキーには使う権限がありません。書き込みません。 $($r.Message)" Red }
        404 { Say "キーは有効ですが、アプリが使うモデル（$model）を使えません: $($r.Message)" Yellow
              $write = Ask-YesNo 'それでも書き込みますか？' }
        400 {
            if ($r.Message -match 'credit') {
                Say 'キーは有効ですが、この組織のクレジットが足りません（このままではアプリの解析が失敗します）。' Yellow
                $write = Ask-YesNo 'それでも書き込みますか？（クレジットを足してから使う場合は Y）'
            } else { Say "確かめられませんでした（$($r.Status)）: $($r.Message)。書き込みません。" Red }
        }
        0   { Say "API につながりませんでした（ネットワークや VPN を確認してください）: $($r.Message)。書き込みません。" Red }
        default { Say "確かめられませんでした（$($r.Status) $($r.Type)）: $($r.Message)。書き込みません。" Red }
    }

    if ($write) {
        if (Write-Key $key) {
            Say 'api_config.dart の claudeApiKey を書き換えました（ほかの行はそのままです）。' Green
            $changed = $true
            $done = $true
            # クリップボードにキーが残っていたら消す
            try { if ((Get-Clipboard -Raw) -match [regex]::Escape($key)) { Set-Clipboard -Value ' '; Say 'クリップボードに残っていたキーを消しました。' DarkGray } } catch {}
        } else {
            Say '書き込みに失敗しました。api_config.dart をエディタで開いていたら閉じて、もう一度実行してください。' Red
        }
    }
    $key = $null
    if (-not $done) {
        if (-not (Ask-YesNo 'もう一度入力しますか？')) { break }
    }
}
$key = $null
[GC]::Collect()

if (-not $done) { Say ''; Say 'キーは書き換えていません。' Yellow; exit 1 }

Say ''
if ($changed) { Say 'アプリに反映するには APK を作り直してスマホに入れ直す必要があります。' White }
if (Ask-YesNo '続けて APK をビルドして、QRDL でスマホに配りますか？') {
    if (Test-Path -LiteralPath $BuildPs1) {
        & powershell -NoProfile -ExecutionPolicy Bypass -File $BuildPs1
    } else {
        Say "ビルド用のスクリプトが見つかりません: $BuildPs1" Red
    }
} else {
    Say "あとでビルドするときは $(Join-Path $Root 'build_apk_qrdl.bat') をダブルクリックしてください。"
}
