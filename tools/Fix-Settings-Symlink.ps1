# Flotsam settings fix - symbolic link method (requires administrator)
#
# Creates <GAME_DIR>\PlayerSettings.json as a symbolic link to the current
# Windows user's LocalLow settings file, so the game's relative-path read and
# absolute-path write resolve to the same file.

param(
    [string]$InstallLocation
)

. (Join-Path $PSScriptRoot 'common.ps1')

Write-Header 'Flotsam 设置修复 - 符号链接方式'

if (-not (Test-IsAdmin)) {
    $extra = @()
    if ($InstallLocation) { $extra += @('-InstallLocation', $InstallLocation) }
    if (Invoke-SelfElevate -ScriptPath $PSCommandPath -ExtraArgs $extra) { exit 0 }
    Read-Pause
    exit 1
}

try {
    $game     = Resolve-FlotsamInstallLocation -InstallLocation $InstallLocation
    $settings = Get-FlotsamSettingsPath
    $link     = Join-Path $game 'PlayerSettings.json'

    if (-not (Test-Path -LiteralPath $settings)) {
        throw "找不到设置文件：`n$settings`n请先启动一次游戏，让游戏生成该文件后再运行本脚本。"
    }
    Assert-GameNotRunning

    Write-Info ("游戏目录: " + $game)
    Write-Info ("设置文件: " + $settings)

    $backupDir = Join-Path $PSScriptRoot 'backup'
    if (-not (Test-Path -LiteralPath $backupDir)) {
        New-Item -ItemType Directory -Path $backupDir -Force | Out-Null
    }
    $stamp  = Get-Date -Format 'yyyyMMdd-HHmmss'
    $backup = Join-Path $backupDir ("PlayerSettings.$stamp.json")
    Copy-Item -LiteralPath $settings -Destination $backup -Force
    Write-Ok ("已备份设置文件 -> " + $backup)

    # Get-Item -Force also returns a DANGLING symlink (Test-Path would return false),
    # so an old link whose target disappeared cannot block re-creation.
    $existing = Get-Item -LiteralPath $link -Force -ErrorAction SilentlyContinue
    if ($existing) {
        if ($existing.LinkType) {
            Remove-Item -LiteralPath $link -Force
            Write-Info '已删除旧的符号链接。'
        } else {
            $moved = Join-Path $backupDir ("install-dir-PlayerSettings.$stamp.json")
            Move-Item -LiteralPath $link -Destination $moved -Force
            Write-Info ("游戏目录里原有的普通文件已移走 -> " + $moved)
        }
    }

    New-Item -ItemType SymbolicLink -Path $link -Target $settings | Out-Null

    $after = Get-Item -LiteralPath $link -Force
    if (-not $after.LinkType) {
        throw '符号链接创建失败（可能没有管理员权限）。'
    }
    Write-Ok '符号链接已创建：'
    Write-Info ("  " + $link + "  ->  " + $settings)

    $json = Get-Content -LiteralPath $link -Raw -Encoding UTF8 | ConvertFrom-Json
    Write-Ok '通过链接读取设置正常，当前值：'
    Write-Info ('  主音量={0}  音乐={1}  UI={2}  音效={3}  界面缩放={4}  垂直同步={5}' -f `
        $json.AudioPlayerData.MasterVolume, $json.AudioPlayerData.MusicVolume,
        $json.AudioPlayerData.UIVolume, $json.AudioPlayerData.SFXVolume,
        $json.GraphicsPlayerData.UIScale, $json.GraphicsPlayerData.VSync)

    Write-Host ''
    Write-Ok '修复完成。请启动游戏，修改一次设置，退出后再进入验证。'
    Write-Host ''
    Write-Info '撤销：运行 Undo-Settings-Symlink.bat'
} catch {
    Write-Err $_.Exception.Message
}

Read-Pause

