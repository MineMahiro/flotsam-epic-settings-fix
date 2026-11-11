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

# Path of the real settings file for the CURRENT Windows user.
# Prefers the Windows known-folder API (handles redirected profiles), then env vars.
function Get-FlotsamSettingsPath {
    $localAppData = $null
    try { $localAppData = [Environment]::GetFolderPath('LocalApplicationData') } catch { }
    if (-not $localAppData) { $localAppData = $env:LOCALAPPDATA }
    if ($localAppData) {
        $base = Join-Path (Split-Path -Parent $localAppData) 'LocalLow'
    } elseif ($env:USERPROFILE) {
        $base = Join-Path $env:USERPROFILE 'AppData\LocalLow'
    } else {
        throw '无法确定当前用户的 LocalLow 目录（USERPROFILE / LOCALAPPDATA 均不可用）。'
    }
    return (Join-Path $base 'Pajama Llama Games\Flotsam\PlayerSettings.json')
}

# Directories where the Epic Games Launcher stores its install manifests.
function Get-FlotsamManifestDirectories {
    $dirs = @()
    if ($env:ProgramData) {
        $dirs += (Join-Path $env:ProgramData 'Epic\EpicGamesLauncher\Data\Manifests')
    }
    $dirs += 'C:\ProgramData\Epic\EpicGamesLauncher\Data\Manifests'
    return @($dirs | Select-Object -Unique)
}

# Local drive roots only; skips UNC mappings (Test-Path on an offline network
# drive can block for many seconds).
function Get-LocalDriveRoots {
    $roots = @()
    foreach ($d in @(Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue)) {
        if (-not $d.Root) { continue }
        if ($d.Root -like '\\*') { continue }
        $roots += $d.Root
    }
    return @($roots | Select-Object -Unique)
}

# Locate the Flotsam install folder on THIS machine.
# 1) Epic launcher manifests (handles any install location chosen in Epic)
# 2) common folder layouts on local drives
# 3) one-level scan for a folder named "Flotsam"
function Get-FlotsamInstallLocation {
    foreach ($manifestDir in (Get-FlotsamManifestDirectories)) {
        if (-not (Test-Path -LiteralPath $manifestDir)) { continue }
        foreach ($file in @(Get-ChildItem -LiteralPath $manifestDir -Filter '*.item' -ErrorAction SilentlyContinue)) {
            $raw = $null
            try { $raw = Get-Content -LiteralPath $file.FullName -Raw -Encoding UTF8 } catch { continue }
            if (-not $raw) { continue }
            if ($raw -notmatch 'Flotsam') { continue }
            if ($raw -match '"InstallLocation"\s*:\s*"((?:[^"\\]|\\.)+)"') {
                $loc = $matches[1] -replace '\\\\', '\'
                if ($loc -and (Test-Path -LiteralPath (Join-Path $loc 'Flotsam.exe'))) { return $loc }
            }
        }
    }

    $layouts = @(
        'Epic Games\Flotsam',
        'EpicGames\Flotsam',
        'Program Files\Epic Games\Flotsam',
        'Program Files (x86)\Epic Games\Flotsam',
        'Game\Flotsam',
        'Games\Flotsam',
        'Software\Games\Flotsam',
        'Software\Flotsam',
        'Flotsam'
    )
    foreach ($root in (Get-LocalDriveRoots)) {
        foreach ($sub in $layouts) {
            $candidate = Join-Path $root $sub
            if (Test-Path -LiteralPath (Join-Path $candidate 'Flotsam.exe')) { return $candidate }
        }
    }

    foreach ($root in (Get-LocalDriveRoots)) {
        try { $children = @(Get-ChildItem -LiteralPath $root -Directory -ErrorAction Stop) } catch { continue }
        foreach ($child in $children) {
            if ($child.Name -ieq 'Flotsam' -and (Test-Path -LiteralPath (Join-Path $child.FullName 'Flotsam.exe'))) {
                return $child.FullName
            }
            $candidate = Join-Path $child.FullName 'Flotsam'
            if (Test-Path -LiteralPath (Join-Path $candidate 'Flotsam.exe')) { return $candidate }
        }
    }
    return $null
}

function Resolve-FlotsamInstallLocation {
    param([string]$InstallLocation)
    if (-not $InstallLocation -and $env:FLOTSAM_FIX_GAME_DIR) { $InstallLocation = $env:FLOTSAM_FIX_GAME_DIR }
    if ($InstallLocation) {
        if (Test-Path -LiteralPath (Join-Path $InstallLocation 'Flotsam.exe')) { return $InstallLocation }
        throw "指定的游戏目录无效（其中没有 Flotsam.exe）：$InstallLocation"
    }
    $found = Get-FlotsamInstallLocation
    if (-not $found) {
        throw ('没有找到 Flotsam 安装目录。请用 -InstallLocation "X:\path\to\Flotsam" 参数指定，' +
               '或设置环境变量 FLOTSAM_FIX_GAME_DIR。')
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

# True if a probe file can be created in $Path.
function Test-DirectoryWritable {
    param([string]$Path)
    try {
        $probe = Join-Path $Path ('.flotsam-fix-write-test-' + [guid]::NewGuid().ToString('N'))
        [System.IO.File]::WriteAllText($probe, 'x')
        Remove-Item -LiteralPath $probe -Force -ErrorAction SilentlyContinue
        return $true
    } catch {
        return $false
    }
}

function Invoke-SelfElevate {
    param(
        [string]$ScriptPath,
        [string[]]$ExtraArgs = @()
    )
    Write-Warn '该操作需要管理员权限，正在请求 UAC 授权...'
    $argList = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', ('"' + $ScriptPath + '"'))
    foreach ($a in $ExtraArgs) {
        if ($a -match '\s') { $argList += ('"' + $a + '"') } else { $argList += $a }
    }
    try {
        Start-Process -FilePath 'powershell.exe' -Verb RunAs -Wait -ArgumentList $argList
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

