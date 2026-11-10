# Flotsam settings fix - shared helpers (PowerShell 5.1+)

$ErrorActionPreference = 'Stop'

function Write-Header([string]$text) {
    Write-Host ''
    Write-Host ('=' * 62) -ForegroundColor Cyan
    Write-Host (' ' + $text) -ForegroundColor Cyan
    Write-Host ('=' * 62) -ForegroundColor Cyan
}

function Write-Ok([string]$text)   { Write-Host ('[OK]    ' + $text) -ForegroundColor Green }
function Write-Warn([string]$text) { Write-Host ('[WARN]  ' + $text) -ForegroundColor Yellow }
function Write-Err([string]$text)  { Write-Host ('[ERROR] ' + $text) -ForegroundColor Red }
function Write-Info([string]$text) { Write-Host ('        ' + $text) -ForegroundColor Gray }

function Test-IsAdmin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($id)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-FlotsamSettingsPath {
    return (Join-Path $env:USERPROFILE 'AppData\LocalLow\Pajama Llama Games\Flotsam\PlayerSettings.json')
}

# Try to find the game install folder from the Epic Games Launcher manifests,
# then fall back to a few common locations.
function Get-FlotsamInstallLocation {
    $manifestDir = 'C:\ProgramData\Epic\EpicGamesLauncher\Data\Manifests'
    if (Test-Path -LiteralPath $manifestDir) {
        foreach ($file in @(Get-ChildItem -LiteralPath $manifestDir -Filter '*.item' -ErrorAction SilentlyContinue)) {
            $raw = $null
            try { $raw = Get-Content -LiteralPath $file.FullName -Raw -Encoding UTF8 } catch { continue }
            if ($raw -and ($raw -match 'Flotsam')) {
                $loc = $null
                if ($raw -match '"InstallLocation"\s*:\s*"([^"]+)"') {
                    $loc = $matches[1] -replace '\\\\', '\'
                }
                if ($loc -and (Test-Path -LiteralPath (Join-Path $loc 'Flotsam.exe'))) {
                    return $loc
                }
            }
        }
    }
    # scan fixed/removable drives for the usual "Game(s)\Flotsam" layouts
    foreach ($drive in @(Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue)) {
        if (-not $drive.Root) { continue }
        foreach ($sub in @('Game\Flotsam','Games\Flotsam','Flotsam')) {
            $candidate = Join-Path $drive.Root $sub
            if (Test-Path -LiteralPath (Join-Path $candidate 'Flotsam.exe')) { return $candidate }
        }
    }
    foreach ($c in @('C:\Program Files\Flotsam','C:\Program Files (x86)\Flotsam')) {
        if (Test-Path -LiteralPath (Join-Path $c 'Flotsam.exe')) { return $c }
    }
    return $null
}

function Resolve-FlotsamInstallLocation {
    param([string]$InstallLocation)
    if ($InstallLocation) {
        if (Test-Path -LiteralPath (Join-Path $InstallLocation 'Flotsam.exe')) { return $InstallLocation }
        throw "指定的游戏目录无效（其中没有 Flotsam.exe）：$InstallLocation"
    }
    $found = Get-FlotsamInstallLocation
    if (-not $found) {
        throw '没有找到 Flotsam 安装目录。请用 -InstallLocation "X:\path\to\Flotsam" 参数指定。'
    }
    return $found
}

function Get-FlotsamAssemblyPath {
    param([string]$InstallLocation)
    return (Join-Path $InstallLocation 'Flotsam_Data\Managed\Assembly-CSharp.dll')
}

function Assert-GameNotRunning {
    $proc = Get-Process -Name 'Flotsam' -ErrorAction SilentlyContinue
    if ($proc) { throw '游戏正在运行，请先完全退出 Flotsam 再运行本脚本。' }
}

function Invoke-SelfElevate {
    param([string]$ScriptPath)
    Write-Warn '该操作需要管理员权限，正在请求 UAC 授权...'
    $args = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', ('"' + $ScriptPath + '"'))
    try {
        Start-Process -FilePath 'powershell.exe' -Verb RunAs -Wait -ArgumentList $args
    } catch {
        Write-Err '提权失败或被取消。请右键对应的 .bat 文件 -> 以管理员身份运行。'
        return $false
    }
    return $true
}


function Read-Pause {
    if ($env:FLOTSAM_FIX_NONINTERACTIVE -eq '1') { return }
    Read-Host '按回车退出' | Out-Null
}


