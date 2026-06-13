# ==============================================================
# DingAI - Windows Setup Script
# Usage: irm https://raw.githubusercontent.com/YumingMa/dingtalk-ai-persona/main/install.ps1 -OutFile $env:TEMP\ai-setup.ps1; & $env:TEMP\ai-setup.ps1
# ==============================================================

# ── Admin config (edit before deployment) ─────────────────────
$HAI_GATEWAY_URL   = "https://api.hai.network/unified-preview/openai"
$HAI_GATEWAY_MODEL = "claude-sonnet-4-6"
$INSTALL_DIR       = "$env:USERPROFILE\ai-persona"
$GITHUB_RAW        = "https://raw.githubusercontent.com/YumingMa/dingtalk-ai-persona/main"
# ──────────────────────────────────────────────────────────────

$ErrorActionPreference = "Stop"
$ProgressPreference    = "SilentlyContinue"

function Write-Step($n, $text) {
    Write-Host ""
    Write-Host "  [$n] $text" -ForegroundColor Cyan
    Write-Host "  $('─' * 48)" -ForegroundColor DarkGray
}
function Write-Ok($t)   { Write-Host "  [OK] $t" -ForegroundColor Green }
function Write-Info($t) { Write-Host "  --> $t" -ForegroundColor Gray }
function Write-Warn($t) { Write-Host "  [!] $t" -ForegroundColor Yellow }
function Pause-Key($t = "Press any key to continue...") {
    Write-Host "  $t" -ForegroundColor DarkGray -NoNewline
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
    Write-Host ""
}
function Read-Input($prompt, $default = "") {
    if ($default) {
        Write-Host "  $prompt [$default]: " -ForegroundColor White -NoNewline
    } else {
        Write-Host "  ${prompt}: " -ForegroundColor White -NoNewline
    }
    $val = Read-Host
    if ([string]::IsNullOrWhiteSpace($val) -and $default) { return $default }
    return $val
}
function Read-Secret($prompt) {
    Write-Host "  ${prompt}: " -ForegroundColor White -NoNewline
    $val = Read-Host -AsSecureString
    return [System.Runtime.InteropServices.Marshal]::PtrToStringAuto(
        [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($val))
}
function Refresh-Path {
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" +
                [System.Environment]::GetEnvironmentVariable("Path","User")
}
function Download-File($url, $dest) {
    Invoke-WebRequest -Uri $url -OutFile $dest -UseBasicParsing
}

# ── Welcome ───────────────────────────────────────────────────
Clear-Host
Write-Host ""
Write-Host "  ============================================" -ForegroundColor Cyan
Write-Host "       DingAI - Personal AI Assistant         " -ForegroundColor Cyan
Write-Host "  ============================================" -ForegroundColor Cyan
Write-Host ""
Pause-Key "Press any key to start (about 5 minutes)..."

# ════════════════════════════════════════════════════
# Step 1: Python
# ════════════════════════════════════════════════════
Write-Step 1 "Check / Install Python 3.10+"

$pyCmd = ""
foreach ($cmd in @("python", "python3", "py")) {
    try {
        $ver = & $cmd --version 2>&1
        if ($ver -match "Python (\d+)\.(\d+)") {
            if ([int]$Matches[1] -ge 3 -and [int]$Matches[2] -ge 10) {
                $pyCmd = $cmd
                Write-Ok "Python $ver already installed"
                break
            }
        }
    } catch {}
}

if (-not $pyCmd) {
    Write-Info "Python not found, installing via winget..."
    try {
        winget install -e --id Python.Python.3.12 --silent --accept-package-agreements --accept-source-agreements
        Refresh-Path
        $pyCmd = "python"
        Write-Ok "Python installed"
    } catch {
        Write-Warn "Auto install failed. Please install Python manually:"
        Write-Host "  https://www.python.org/downloads/" -ForegroundColor Yellow
        Write-Host "  (check 'Add Python to PATH' during installation)" -ForegroundColor Yellow
        Pause-Key "After installation, press any key to continue..."
        Refresh-Path
        $pyCmd = "python"
    }
}

# ════════════════════════════════════════════════════
# Step 2: dws
# ════════════════════════════════════════════════════
Write-Step 2 "Install dws DingTalk CLI"

if (Get-Command dws -ErrorAction SilentlyContinue) {
    $v = (& dws version 2>$null | Select-String "Version").ToString().Trim()
    Write-Ok "dws already installed: $v"
} else {
    Write-Info "Downloading dws..."
    try {
        $dwsScript = "$env:TEMP\dws-install.ps1"
        Download-File "https://raw.githubusercontent.com/DingTalk-Real-AI/dingtalk-workspace-cli/main/scripts/install.ps1" $dwsScript
        & $dwsScript
        Refresh-Path
        Write-Ok "dws installed"
    } catch {
        Write-Warn "Auto install failed. Please install manually:"
        Write-Host "  irm https://raw.githubusercontent.com/DingTalk-Real-AI/dingtalk-workspace-cli/main/scripts/install.ps1 -OutFile dws-install.ps1; & .\dws-install.ps1" -ForegroundColor Yellow
        Pause-Key "After installation, press any key to continue..."
        Refresh-Path
    }
}

# ════════════════════════════════════════════════════
# Step 3: Download project files
# ════════════════════════════════════════════════════
Write-Step 3 "Download AI Persona project files"

New-Item -ItemType Directory -Force $INSTALL_DIR | Out-Null
Write-Ok "Directory: $INSTALL_DIR"

$files = @(
    "requirements.txt",
    "config.py",
    "dws_runner.py",
    "session.py",
    "lightchat.py",
    "dws_tools.py",
    "agent.py",
    "bot.py",
    "main.py"
)

foreach ($f in $files) {
    Write-Info "Downloading $f..."
    Download-File "$GITHUB_RAW/$f" "$INSTALL_DIR\$f"
}
Write-Ok "All files downloaded"

# ════════════════════════════════════════════════════
# Step 4: Install Python dependencies
# ════════════════════════════════════════════════════
Write-Step 4 "Install Python dependencies"

Set-Location $INSTALL_DIR
try {
    & $pyCmd -m pip install -r requirements.txt -q
    Write-Ok "Dependencies installed"
} catch {
    Write-Warn "pip failed, trying mirror..."
    try {
        & $pyCmd -m pip install -r requirements.txt -q -i https://pypi.tuna.tsinghua.edu.cn/simple/
        Write-Ok "Dependencies installed (mirror)"
    } catch {
        Write-Warn "Please run manually: pip install -r requirements.txt"
        Pause-Key "After installation, press any key to continue..."
    }
}

# ════════════════════════════════════════════════════
# Step 5: DingTalk login
# ════════════════════════════════════════════════════
Write-Step 5 "DingTalk authorization"

$authOk = $false
try {
    $status = & dws auth status 2>$null | ConvertFrom-Json -ErrorAction SilentlyContinue
    $authOk = ($status -and $status.authenticated -eq $true)
} catch {}

if ($authOk) {
    Write-Ok "Already logged in, skip"
} else {
    Write-Host ""
    Write-Host "  A browser will open for DingTalk scan-to-login." -ForegroundColor White
    Pause-Key "Press any key to open..."
    & dws auth login --device
    Write-Ok "DingTalk login successful"
}

# ════════════════════════════════════════════════════
# Step 6: Create AI persona robot
# ════════════════════════════════════════════════════
Write-Step 6 "Create your AI persona robot"

$APP_KEY = ""
$APP_SECRET = ""

Write-Info "Creating personal AI persona robot on DingTalk Open Platform..."

try {
    $robotOut = & dws devapp robot create `
        --app-name "MyAIPersona" `
        --robot-name "AI Persona" `
        --desc "My DingTalk AI Assistant" `
        --yes --format json 2>$null
    $robot = $robotOut | ConvertFrom-Json -ErrorAction SilentlyContinue
    # Use if/elseif to avoid -or converting strings to boolean
    if     ($robot.clientId)           { $APP_KEY = [string]$robot.clientId }
    elseif ($robot.appKey)             { $APP_KEY = [string]$robot.appKey }
    elseif ($robot.result.clientId)    { $APP_KEY = [string]$robot.result.clientId }
    if     ($robot.clientSecret)       { $APP_SECRET = [string]$robot.clientSecret }
    elseif ($robot.appSecret)          { $APP_SECRET = [string]$robot.appSecret }
    elseif ($robot.result.clientSecret){ $APP_SECRET = [string]$robot.result.clientSecret }
} catch {}

if (-not $APP_KEY) {
    Write-Warn "Auto creation failed. Please create manually:"
    Write-Host ""
    Write-Host "  Option 1 (command):" -ForegroundColor White
    Write-Host "  dws devapp robot create --app-name MyAIPersona --robot-name AIPersona --yes" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  Option 2 (web):" -ForegroundColor White
    Write-Host "  https://open-dev.dingtalk.com -> App Dev -> Create App -> Enable Robot -> Stream mode" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  Note: If prompted 'no developer permission', ask admin to add you at:" -ForegroundColor DarkGray
    Write-Host "  https://open-dev.dingtalk.com (Permission Management -> Add Developer)" -ForegroundColor DarkGray
    Write-Host ""
    $APP_KEY    = Read-Input "Enter AppKey (clientId)"
    $APP_SECRET = Read-Secret "Enter AppSecret (clientSecret)"
}

if (-not $APP_KEY)    { Write-Host "  [ERROR] AppKey cannot be empty" -ForegroundColor Red; exit 1 }
if (-not $APP_SECRET) { Write-Host "  [ERROR] AppSecret cannot be empty" -ForegroundColor Red; exit 1 }
Write-Ok "Robot configured: AppKey $($APP_KEY.Substring(0, [Math]::Min(8, $APP_KEY.Length)))..."

# ════════════════════════════════════════════════════
# Step 7: HAI Gateway Token
# ════════════════════════════════════════════════════
Write-Step 7 "Configure HAI Gateway"

Write-Host ""
Write-Host "  HAI Gateway is the company AI service. Each user has their own token." -ForegroundColor White
Write-Host "  Contact admin to get your personal token." -ForegroundColor DarkGray
Write-Host ""

if ($HAI_GATEWAY_URL -eq "https://api.hai.network/unified-preview/openai") {
    Write-Host "  Gateway URL: $HAI_GATEWAY_URL (pre-configured)" -ForegroundColor DarkGray
} else {
    $HAI_GATEWAY_URL = Read-Input "HAI Gateway URL"
}

$HAI_TOKEN = Read-Secret "Your HAI Gateway Token"
if ([string]::IsNullOrWhiteSpace($HAI_TOKEN)) {
    Write-Host "  [ERROR] Token cannot be empty" -ForegroundColor Red; exit 1
}

$HAI_GATEWAY_MODEL = Read-Input "Model name" $HAI_GATEWAY_MODEL
Write-Ok "HAI Gateway configured"

# ════════════════════════════════════════════════════
# Step 8: Write .env
# ════════════════════════════════════════════════════
Write-Step 8 "Generate config file"

$envContent = @"
DINGTALK_APP_KEY=$APP_KEY
DINGTALK_APP_SECRET=$APP_SECRET
ANTHROPIC_API_KEY=$HAI_TOKEN
ANTHROPIC_BASE_URL=$HAI_GATEWAY_URL
ANTHROPIC_DEFAULT_SONNET_MODEL=$HAI_GATEWAY_MODEL
"@
[System.IO.File]::WriteAllText("$INSTALL_DIR\.env", $envContent, [System.Text.Encoding]::UTF8)
Write-Ok ".env written to $INSTALL_DIR\.env"

# ════════════════════════════════════════════════════
# Step 9: Create desktop shortcut
# ════════════════════════════════════════════════════
Write-Step 9 "Create desktop shortcut"

$batContent = "@echo off`r`ncd /d `"$INSTALL_DIR`"`r`n$pyCmd main.py`r`npause"
[System.IO.File]::WriteAllText("$INSTALL_DIR\start.bat", $batContent, [System.Text.Encoding]::ASCII)

$desktop = [System.Environment]::GetFolderPath("Desktop")
$shortcut = (New-Object -ComObject WScript.Shell).CreateShortcut("$desktop\AI Persona.lnk")
$shortcut.TargetPath  = "$INSTALL_DIR\start.bat"
$shortcut.Description = "Start DingTalk AI Persona"
$shortcut.IconLocation = "shell32.dll,13"
$shortcut.Save()

Write-Ok "Desktop shortcut created"

# ── Done ──────────────────────────────────────────────────────
Write-Host ""
Write-Host "  ============================================" -ForegroundColor Green
Write-Host "       Setup Complete!                        " -ForegroundColor Green
Write-Host "  ============================================" -ForegroundColor Green
Write-Host ""
Write-Host "  Next time: double-click 'AI Persona' on your desktop" -ForegroundColor White
Write-Host ""
Write-Host "  Starting now..." -ForegroundColor Cyan
Write-Host ""
Pause-Key "Press any key to launch..."

Set-Location $INSTALL_DIR
& $pyCmd main.py
