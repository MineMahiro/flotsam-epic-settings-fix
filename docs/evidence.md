# 实测证据（已在真实机器上验证）

> 说明：以下数据来自一台实际遇到该问题的 Windows 机器，已隐去用户名、账号 ID、机器名等个人信息。
> 游戏版本：Epic build `1.0.1f9`，Unity `6000.3.26f1`。

## 1. 设置文件内容 = 代码默认值

`%USERPROFILE%\AppData\LocalLow\Pajama Llama Games\Flotsam\PlayerSettings.json`（修复前）：

```json
{"HasMigratedSaves":false,
 "AudioPlayerData":{"FMOD":true,"MasterVolume":0.8,"MusicVolume":0.8,"UIVolume":0.8,"SFXVolume":0.8},
 "GameplayPlayerData":{"ForceMouseAndKeyboard":false,"EdgeScrolling":true,"InvertHorizontalRotation":false,
   "InvertVerticalRotation":false,"InvertScrolling":false,"RotationSensitivity":0.5,"MovementSensitivity":0.5,
   "ScrollingSensitivity":0.5,"SelectedLanguageIndex":0,"AutosaveLimit":5,
   "ToggleGeneralStorageFilters":true,"SnapBuilding":true,"ShowBuildingGrid":true},
 "GraphicsPlayerData":{"UIScale":1.0,"VSync":true}}
```

与 `Settings.ResetToDefaults()` 写出的默认值逐项一致（见 `docs/root-cause.md` 第 3.3 节表格）。

## 2. 时间线

- 文件 `CreationTime` 与一次启动会话对应；
- `LastWriteTime` 每次都落在「游戏启动后约 30 秒」附近，说明是**启动阶段**被重写；
- 用户多次「启动 → 改设置 → 退出 → 再启动」后，文件内容始终回到上面这份默认值。

## 3. Epic 侧排查（说明不是启动器的问题）

Epic 启动器日志里该游戏的产品状态（`get-installed-apps-response`）：

```json
{"appName":"<app>","isInstalled":true,"installedVersion":"1.0.1f9",
 "isCorrupt":false,"isCloudSyncing":false,"supportsCloudSave":false,
 "hasUpdate":false,"installLocation":"<GAME_DIR>"}
```

云同步日志显示其同步范围为：

```
Cloud Sync: Chunk Directory ... from
%USERPROFILE%/AppData/LocalLow/Pajama Llama Games/Flotsam/Saves/   ← 仅存档目录，12 个 .fs 文件
```

**从不包含 `PlayerSettings.json`。**

## 4. 修复后的实测验证

以程序集补丁方式修复后，直接启动一次游戏（约 90 秒，随后结束进程）：

| 观察项 | 结果 |
|---|---|
| 游戏进程 | 正常启动并持续运行，`Player.log` 无程序集加载错误、无崩溃 |
| EOS 登录 / 商店 / 成就 | 正常 |
| 存档文件访问时间 | 12 个 `.fs` 文件在启动后约 30 秒被读取 → 证明执行到了玩家档案加载流程 |
| `PlayerSettings.json` 的 `LastWriteTime` | **保持不变**（没有再次被默认值覆盖） |
| `PlayerSettings.json` 内容哈希 | 保持不变 |
| 存档 `LastWriteTime` | 全部保持原样，未被改动 |

结论：修复后设置读取成功，不再触发「读失败 → 写默认值」的破坏逻辑。

## 5. 补丁一致性校验

- 补丁前/后逐指令比对：**只有 1 条 `ldstr` 指令不同**；
- 类型数量 3634 / 3634 一致；
- `Settings` 类型成员数 30 / 30 一致。

| 版本 | SHA256 | 大小 |
|---|---|---|
| 原始 DLL | `5B5C9F730ED71D5F66C0267064FC57667D2FF5644A018E9189B140CE025C1CD8` | 4,093,440 |
| 补丁后 DLL | `D089853629F591BD3D167A7914ABB670A0FD4CB45DA5154B9A6015E43B874F24` | 4,070,912 |
