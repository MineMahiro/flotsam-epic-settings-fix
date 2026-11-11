# Flotsam settings fix - assembly patch
#
# Patches ONE string literal inside Settings::Load() in Assembly-CSharp.dll:
#   ldstr "PlayerSettings.json"  ->  ldstr "<absolute path of PlayerSettings.json on THIS machine>"
# The path is computed when the script runs, so it is correct for the current
# Windows user and install location. A backup of the original DLL is created
# next to it before patching.

param(
    [string]$InstallLocation,
    [switch]$Force
)

. (Join-Path $PSScriptRoot 'common.ps1')

Write-Header 'Flotsam 设置修复 - 程序集补丁'

# Known-tested original DLL hashes (informational only)
$knownHashes = @{
    '5B5C9F730ED71D5F66C0267064FC57667D2FF5644A018E9189B140CE025C1CD8' = 'Epic build 1.0.1f9 / Unity 6000.3.26f1'
}

try {
    Assert-GameNotRunning

    $game = Resolve-FlotsamInstallLocation -InstallLocation $InstallLocation
    $dll  = Get-FlotsamAssemblyPath -InstallLocation $game
    if (-not (Test-Path -LiteralPath $dll)) {
        throw ("找不到游戏程序集：`n" + $dll)
    }
    $managedDir   = Split-Path -Parent $dll
    $settingsPath = Get-FlotsamSettingsPath
    $cecilPath    = Join-Path $PSScriptRoot 'lib\Mono.Cecil.dll'
    if (-not (Test-Path -LiteralPath $cecilPath)) {
        throw ('缺少依赖库：' + $cecilPath)
    }

    Write-Info ('游戏目录  : ' + $game)
    Write-Info ('程序集    : ' + $dll)
    Write-Info ('设置文件  : ' + $settingsPath)

    # Writing next to the DLL fails for non-admins when the game lives under
    # "C:\Program Files" (common for Epic default installs). Elevate instead of
    # failing with a raw "access denied".
    if (-not (Test-DirectoryWritable -Path $managedDir)) {
        if (-not (Test-IsAdmin)) {
            Write-Warn ('游戏目录不可写（常见于安装到 Program Files），需要管理员权限继续：' + $managedDir)
            $extra = @('-InstallLocation', $game)
            if ($Force) { $extra += '-Force' }
            if (Invoke-SelfElevate -ScriptPath $PSCommandPath -ExtraArgs $extra) { exit 0 }
            throw '已取消。也可以改用符号链接方案（Fix-Settings-Symlink.bat）。'
        }
        throw ('游戏目录不可写：' + $managedDir)
    }
    if (-not (Test-Path -LiteralPath $settingsPath)) {
        Write-Warn '设置文件还不存在（游戏尚未运行过）。补丁仍会安装，游戏首次运行后会生成该文件。'
    }

    # NOTE: .NET Framework may refuse Assembly.LoadFrom on paths it does not consider
    # the "MyComputer" zone (HRESULT 0x80131515). Loading from a byte array avoids that.
    $cecilBytes = [System.IO.File]::ReadAllBytes($cecilPath)
    [void][System.Reflection.Assembly]::Load($cecilBytes)

    $beforeHash = (Get-FileHash -LiteralPath $dll -Algorithm SHA256).Hash
    Write-Info ('SHA256    : ' + $beforeHash)
    if ($knownHashes.ContainsKey($beforeHash)) {
        Write-Ok ('已知测试版本：' + $knownHashes[$beforeHash])
    } else {
        Write-Warn '这不是已知的测试版本（游戏可能已更新），仍会按 IL 特征尝试。'
        if (-not $Force) {
            $ans = Read-Host '是否继续？(Y/N)'
            if ($ans -notmatch '^[Yy]') { throw '已取消。' }
        }
    }

    $resolver = New-Object Mono.Cecil.DefaultAssemblyResolver
    $resolver.AddSearchDirectory($managedDir)
    if ($env:FLOTSAM_FIX_RESOLVER_DIR -and (Test-Path -LiteralPath $env:FLOTSAM_FIX_RESOLVER_DIR)) {
        $resolver.AddSearchDirectory($env:FLOTSAM_FIX_RESOLVER_DIR)
    }

    $readerParams = New-Object Mono.Cecil.ReaderParameters
    $readerParams.AssemblyResolver = $resolver

    $asm = [Mono.Cecil.AssemblyDefinition]::ReadAssembly($dll, $readerParams)
    try {
        $type = $asm.MainModule.GetType('Settings')
        if (-not $type) { throw '没有找到 Settings 类型，游戏版本可能已变化。请改用符号链接方式。' }

        $method = $null
        foreach ($m in $type.Methods) {
            if ($m.Name -eq 'Load' -and $m.HasBody) { $method = $m; break }
        }
        if (-not $method) { throw '没有找到 Settings.Load 方法，游戏版本可能已变化。请改用符号链接方式。' }

        $replaced = 0
        $already  = 0
        foreach ($ins in $method.Body.Instructions) {
            if ($ins.OpCode.Code -eq [Mono.Cecil.Cil.Code]::Ldstr) {
                $val = [string]$ins.Operand
                if ($val -eq 'PlayerSettings.json') {
                    $ins.Operand = $settingsPath
                    $replaced++
                } elseif ($val -eq $settingsPath) {
                    $already++
                }
            }
        }

        if ($replaced -eq 0) {
            if ($already -gt 0) {
                Write-Ok '该游戏已经打过补丁，无需重复操作。'
                Read-Pause
                exit 0
            }
            throw '没有找到目标指令（Settings.Load 中的 "PlayerSettings.json"），无法打补丁。请改用符号链接方式。'
        }

        # backup + write
        $stamp  = Get-Date -Format 'yyyyMMdd-HHmmss'
        $backup = $dll + '.original.bak-' + $stamp
        Copy-Item -LiteralPath $dll -Destination $backup -Force
        Write-Ok ('已备份原始 DLL -> ' + $backup)

        $temp = $dll + '.patched.tmp'
        $writerParams = New-Object Mono.Cecil.WriterParameters
        $asm.Write($temp, $writerParams)
    } finally {
        if ($asm) { $asm.Dispose() }
    }

    # read-back verification
    $verifyParams = New-Object Mono.Cecil.ReaderParameters
    $verifyParams.AssemblyResolver = $resolver
    $vAsm = [Mono.Cecil.AssemblyDefinition]::ReadAssembly($temp, $verifyParams)
    try {
        $vMethod = $vAsm.MainModule.GetType('Settings').Methods | Where-Object { $_.Name -eq 'Load' -and $_.HasBody } | Select-Object -First 1
        $found = $false
        foreach ($ins in $vMethod.Body.Instructions) {
            if ($ins.OpCode.Code -eq [Mono.Cecil.Cil.Code]::Ldstr -and [string]$ins.Operand -eq $settingsPath) { $found = $true }
        }
        if (-not $found) { throw '补丁回读校验失败（写入后找不到绝对路径）。' }
    } finally {
        $vAsm.Dispose()
    }
    Write-Ok '补丁回读校验通过。'

    Move-Item -LiteralPath $temp -Destination $dll -Force
    $afterHash = (Get-FileHash -LiteralPath $dll -Algorithm SHA256).Hash
    Write-Ok '补丁已安装。'
    Write-Info ('新 SHA256: ' + $afterHash)

    Write-Host ''
    Write-Ok '修复完成。请启动游戏，修改一次设置，退出后再进入验证。'
    Write-Host ''
    Write-Info '还原：运行 Restore-Assembly.bat'
    Write-Info '注意：游戏更新或 Epic「验证文件完整性」会还原 DLL，届时重新运行本脚本即可。'
} catch {
    if ($temp -and (Test-Path -LiteralPath $temp)) { Remove-Item -LiteralPath $temp -Force -ErrorAction SilentlyContinue }
    Write-Err $_.Exception.Message
}

Read-Pause

