# Flotsam settings fix - restore the original Assembly-CSharp.dll from the newest backup

param(
    [string]$InstallLocation
)

. (Join-Path $PSScriptRoot 'common.ps1')

Write-Header 'Flotsam 设置修复 - 还原原始程序集'

try {
    Assert-GameNotRunning

    $game = Resolve-FlotsamInstallLocation -InstallLocation $InstallLocation
    $dll  = Get-FlotsamAssemblyPath -InstallLocation $game
    if (-not (Test-Path -LiteralPath $dll)) { throw ('找不到游戏程序集：' + $dll) }

    $dir = Split-Path -Parent $dll
    $backups = @(Get-ChildItem -LiteralPath $dir -Filter 'Assembly-CSharp.dll.original.bak-*' -File -ErrorAction SilentlyContinue |
                 Sort-Object LastWriteTime -Descending)

    if ($backups.Count -eq 0) {
        throw ('没有找到备份文件（' + $dir + '\Assembly-CSharp.dll.original.bak-*）。')
    }

    $latest = $backups[0]
    Write-Info ('使用备份: ' + $latest.FullName)
    Copy-Item -LiteralPath $latest.FullName -Destination $dll -Force

    $hash = (Get-FileHash -LiteralPath $dll -Algorithm SHA256).Hash
    Write-Ok '已还原原始程序集（设置重置问题会重新出现）。'
    Write-Info ('SHA256: ' + $hash)
} catch {
    Write-Err $_.Exception.Message
}

Read-Pause


