# 根因分析：Epic 版 Flotsam 设置读取路径错误

> 本文基于对 Epic 版游戏 `Flotsam_Data\Managed\Assembly-CSharp.dll`（Mono / .NET 程序集，非 IL2CPP）的反编译整理。
> 文中路径统一以 `<GAME_DIR>`、`%USERPROFILE%` 表示。

## 1. 结论

游戏设置的**写入**与**读取**使用不同的路径解析方式：

| 方向 | 调用链 | 路径类型 | 结果 |
|---|---|---|---|
| 写入 | `Settings.Save()` → `EpicUser.SaveFile()` → `DefaultUser.DefaultSaveFile()` | `Application.persistentDataPath + "PlayerSettings.json"`（绝对路径） | 正常 |
| 读取 | `Settings.Load()` → `EpicUser.LoadFile("PlayerSettings.json")` → `IOUtility.TryReadAndDecompressAllBytes()` | **相对路径**，相对进程工作目录（游戏安装目录 `<GAME_DIR>`） | `File.Exists` 返回 false |

`<GAME_DIR>\PlayerSettings.json` 并不存在，读取必然失败，随后触发默认值覆盖流程。

## 2. 启动期调用链

```text
Session.OnPlayerProfileLoaded()
  └─ if (!Settings.IsInitialized)
       └─ Settings.Load(user, OnSettingsLoaded)
            └─ user.LoadFile("PlayerSettings.json", callback)          // user = EpicUser
                 └─ EpicUser.LoadFile(name, callback)
                      └─ IOUtility.TryReadAndDecompressAllBytes(name, out data)
                           └─ File.Exists(name)                       // 相对 CWD → <GAME_DIR>\PlayerSettings.json → false
                      └─ callback(StorageActionResult(name, succes:false, data:null))
                           └─ Settings/<>c__DisplayClass25_0::<Load>b__0
                                ├─ result.Succes == false → 跳过反序列化
                                ├─ if (Settings.s_instance == null) Settings.CreateInstance()
                                │     ├─ new Settings() + set_Instance()
                                │     └─ ResetToDefaults()
                                │           ├─ AudioPlayerData.ResetSettings(ApplicationSettings.Instance.MasterVolume)
                                │           ├─ GameplayPlayerData.ResetSettings()
                                │           ├─ GraphicsPlayerData.ResetSettings()
                                │           └─ Save()
                                │                 └─ _user == null（此时尚未赋值）
                                │                    └─ Session.Platform.SaveSettings(this)
                                │                         └─ PlatformEpic.SaveSettings()
                                │                              └─ File.WriteAllBytes(<LocalLow>\PlayerSettings.json, 默认值 JSON)  ← 覆盖
                                └─ Settings._user = user
```

关键点：**读取失败时 `_user` 尚未赋值**，因此 `Save()` 走平台默认保存分支，将默认值写入 LocalLow 中的真实文件。

## 3. 关键 IL 片段

### 3.1 保存路径（绝对路径）

`M4.Session.PlatformEpic::.cctor()`

```text
ldsflda  System.Char System.IO.Path::DirectorySeparatorChar
call     System.String System.Char::ToString()
ldstr    "PlayerSettings.json"
call     System.String System.String::Concat(String,String,String)
call     System.String System.IO.Path::GetFullPath(String)
stsfld   System.String M4.Session.PlatformEpic::SETTINGS_PATH
```

结果：`SETTINGS_PATH = %USERPROFILE%\AppData\LocalLow\Pajama Llama Games\Flotsam\PlayerSettings.json`

### 3.2 读取路径（相对路径；Epic 实现缺少前缀）

`M4.Session.DefaultUser::LoadFile(String, UnityAction<StorageActionResult>)`（正确实现）：

```text
ldarg.1
call     System.Boolean System.IO.Path::IsPathRooted(String)
brtrue.s  ...
ldsfld   System.String M4.Session.DefaultUser::PERSISTENT_DATA_PATH
ldarg.1
call     System.String System.String::Concat(String,String)
...
call     System.Boolean PajamaLlama.Utilities.IOUtility::TryReadAndDecompressAllBytes(String, Byte[]&)
```

`M4.Session.EpicUser::LoadFile(String, UnityAction<StorageActionResult>)`（缺陷实现）：

```text
IL_0000: ldarg.1                                              // 原样使用 "PlayerSettings.json"
IL_0001: ldloca.s V_0
IL_0003: call  PajamaLlama.Utilities.IOUtility::TryReadAndDecompressAllBytes(String, Byte[]&)
```

缺少 `PERSISTENT_DATA_PATH` 前缀拼接，路径因此相对当前工作目录。

### 3.3 读取失败回调（默认值写入）

`Settings/<>c__DisplayClass25_0::<Load>b__0(StorageActionResult)`

```text
IL_0001: callvirt System.Boolean StorageActionResult::get_Succes()
IL_0006: brfalse.s IL_003c
   ... JsonUtility.FromJson<Settings>(...) ; Settings::set_Instance(...) ; (异常) Debug.LogWarning("Unable to load PlayerData: ")
IL_003C: ldsfld Settings Settings::s_instance
IL_0041: brtrue.s IL_0048
IL_0043: call   System.Void Settings::CreateInstance()      // 读取失败 → 创建默认实例
IL_0048: call   Settings Settings::get_Instance()
IL_004D: ldarg.0
IL_004E: ldfld  M4.Session.IUser Settings/<>c__DisplayClass25_0::user
IL_0053: stfld  M4.Session.IUser Settings::_user           // 赋值发生在 CreateInstance 之后
```

`Settings.CreateInstance()`

```text
new Settings()
AudioPlayerData    = new AudioPlayerData(true)
GameplayPlayerData = new GameplayPlayerData()
GraphicsPlayerData = new GraphicsPlayerData()
Settings::set_Instance(...)
Settings::ResetToDefaults()      // 内部最后调用 Save()
```

### 3.4 默认值内容

`Settings.ResetToDefaults()` 写入的默认值与每次启动后被覆盖的文件内容一致：

| 字段 | 默认值 |
|---|---|
| MasterVolume / Music / UI / SFX | `0.8`（来自 `ApplicationSettings` 的 `_masterVolume`） |
| Rotation / Movement / ScrollingSensitivity | `0.5` |
| AutosaveLimit | `5` |
| ForceMouseAndKeyboard / Invert* | `false` |
| EdgeScrolling / ToggleGeneralStorageFilters / SnapBuilding / ShowBuildingGrid | `true` |
| UIScale | `1` |
| VSync | `true` |

## 4. 常见修复方式无效的原因

| 方式 | 无效原因 |
|---|---|
| Epic 验证文件完整性 | 仅校验安装目录清单内文件；设置文件位于 LocalLow，不在校验范围 |
| 关闭云存档 | Flotsam 的 Epic 云同步仅覆盖 `Saves\` 下的 `.fs` 存档，不涉及设置文件 |
| 管理员启动 / 清启动器缓存 / 删除 `Saved\Saves\` | 与该相对路径的解析无关 |
| Epic 日志中的 `isCorrupt: true` | 仅为启动器对安装目录状态的标记，与 LocalLow 中的设置文件无关 |

## 5. 两种修复方案有效的原理

### 5.1 符号链接方案

在 `<GAME_DIR>\PlayerSettings.json` 创建指向 LocalLow 真实文件的符号链接：

| 方向 | 解析过程 | 结果 |
|---|---|---|
| 读取 | 相对 CWD → `<GAME_DIR>\PlayerSettings.json` → 链接 → 真实文件 | 成功 |
| 写入 | 绝对路径 → LocalLow 真实文件 | 同一文件 |

### 5.2 程序集补丁方案

将 `Settings::Load` 中的 `ldstr "PlayerSettings.json"` 改为绝对路径：

| 方向 | 解析过程 | 结果 |
|---|---|---|
| 读取 | 绝对路径 → LocalLow 真实文件 | 成功 |
| 写入 | 不变（原实现即为绝对路径） | 同一文件 |

两种方案均只影响「读取设置文件时使用的路径」，不涉及存档、成就与在线功能。

## 6. 自行复核方法（可选）

游戏为 Mono 程序集，可使用 Mono.Cecil 直接读取 IL：

```csharp
var asm = AssemblyDefinition.ReadAssembly("Assembly-CSharp.dll",
    new ReaderParameters { AssemblyResolver = new DefaultAssemblyResolver() });
var t = asm.MainModule.GetType("Settings");
var m = t.Methods.First(x => x.Name == "Load");
foreach (var ins in m.Body.Instructions)
    if (ins.OpCode == OpCodes.Ldstr) Console.WriteLine(ins.Operand);
// 输出 "PlayerSettings.json" 表示未修复；输出绝对路径表示已应用程序集补丁
```

也可对比 `M4.Session.EpicUser::LoadFile` 与 `M4.Session.DefaultUser::LoadFile` 的实现差异。
