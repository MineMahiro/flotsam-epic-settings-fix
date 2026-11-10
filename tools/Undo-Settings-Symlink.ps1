# Flotsam settings fix - remove the symbolic link created by Fix-Settings-Symlink.ps1

param(
    [string]$InstallLocation
)

. (Join-Path $PSScriptRoot 'common.ps1')

Write-Header 'Flotsam 设置修复 - 撤销符号链接'

try {
    $game = Resolve-FlotsamInstallLocation -InstallLocation $InstallLocation
    $link = Join-Path $game 'PlayerSettings.json'

    if (-not (Test-Path -LiteralPath $link)) {
        Write-Warn ("链接不存在，无需撤销：" + $link)
        Read-Pause
        exit 0
    }

    $item = Get-Item -LiteralPath $link -Force
    if (-not $item.LinkType) {
        Write-Warn '该文件是普通文件（不是本工具创建的符号链接），未做任何处理。'
        Read-Pause
        exit 0
    }

    Remove-Item -LiteralPath $link -Force
    Write-Ok '已删除符号链接。游戏设置会恢复“每次启动被重置”的原状。'
} catch {
    Write-Err $_.Exception.Message
}

Read-Pause


