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
    $managedDir = Split-Path -Parent $dll

    if (-not (Test-DirectoryWritable -Path $managedDir)) {
        if (-not (Test-IsAdmin)) {
            Write-Warn ('游戏目录不可写，需要管理员权限继续：' + $managedDir)
            if (Invoke-SelfElevate -ScriptPath $PSCommandPath -ExtraArgs @('-InstallLocation', $game)) { exit 0 }
            throw '已取消。'
        }
        throw ('游戏目录不可写：' + $managedDir)
    }

    $backups = @(Get-ChildItem -LiteralPath $managedDir -Filter 'Assembly-CSharp.dll.original.bak-*' -File -ErrorAction SilentlyContinue |
                 Sort-Object LastWriteTime -Descending)
    if ($backups.Count -eq 0) {
        throw ('没有找到备份文件（' + $managedDir + '\Assembly-CSharp.dll.original.bak-*）。')
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

