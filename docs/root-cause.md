# 根因分析：Epic 版 Flotsam 设置读取路径错误

> 本文基于对 Epic 版游戏 `Flotsam_Data\Managed\Assembly-CSharp.dll`（Mono / .NET 程序集，非 IL2CPP）的反编译，
> 以及本机运行日志与文件状态的实测。路径统一用 `<GAME_DIR>`、`%USERPROFILE%` 表示。

## 1. 结论

游戏里设置的 **写入** 和 **读取** 使用了不同的路径解析方式：

- 写入：`Settings.Save()` → `EpicUser.SaveFile()` → `DefaultUser.DefaultSaveFile()` → `Application.persistentDataPath + "PlayerSettings.json"`（绝对路径，正确）
- 读取：`Settings.Load()` → `EpicUser.LoadFile("PlayerSettings.json")` → `IOUtility.TryReadAndDecompressAllBytes("PlayerSettings.json")` → `File.Exists` / `FileStream` 使用**相对路径**，相对的是**进程工作目录**（Epic 启动游戏时 = 游戏安装目录 `<GAME_DIR>`）

`<GAME_DIR>\PlayerSettings.json` 从来不存在 → 读取必然失败 → 触发默认值覆盖流程。

## 2. 启动时的调用链

```
Session.OnPlayerProfileLoaded()
  └─ if (!Settings.IsInitialized)
       └─ Settings.Load(user, OnSettingsLoaded)
            └─ user.LoadFile("PlayerSettings.json", callback)     // user = EpicUser
                 └─ EpicUser.LoadFile(name, callback)
                      └─ IOUtility.TryReadAndDecompressAllBytes(name, out data)
                           └─ File.Exists(name)                  // 相对 CWD → <GAME_DIR>\PlayerSettings.json → false
                      └─ callback(StorageActionResult(name, succes:false, data:null))
                           └─ Settings/<>c__DisplayClass25_0::<Load>b__0
                                ├─ result.Succes == false → 跳过反序列化
                                ├─ if (Settings.s_instance == null) Settings.CreateInstance()
                                │     └─ new Settings() + set_Instance()
                                │     └─ ResetToDefaults()
                                │           ├─ AudioPlayerData.ResetSettings(ApplicationSettings.Instance.MasterVolume)
                                │           ├─ GameplayPlayerData.ResetSettings()
                                │           ├─ GraphicsPlayerData.ResetSettings()
                                │           └─ Save()
                                │                 └─ _user == null（此时还没赋值）
                                │                    └─ Session.Platform.SaveSettings(this)
                                │                         └─ PlatformEpic.SaveSettings()
                                │                              └─ File.WriteAllBytes(<LocalLow>\PlayerSettings.json, 默认值 JSON)   ← 覆盖！
                                └─ Settings._user = user
```

关键点：**读失败时 `_user` 还没有被赋值**，所以 `Save()` 走的是平台默认保存分支，把默认值写到真实的 LocalLow 文件。

## 3. 关键 IL 片段

### 3.1 保存：绝对路径

`M4.Session.PlatformEpic::.cctor()`

```
ldsflda  System.Char System.IO.Path::DirectorySeparatorChar
call     System.String System.Char::ToString()
ldstr    "PlayerSettings.json"
call     System.String System.String::Concat(String,String,String)
call     System.String System.IO.Path::GetFullPath(String)
stsfld   System.String M4.Session.PlatformEpic::SETTINGS_PATH
```

→ `SETTINGS_PATH = %USERPROFILE%\AppData\LocalLow\Pajama Llama Games\Flotsam\PlayerSettings.json`

### 3.2 读取：Epic 实现漏了路径前缀

`M4.Session.DefaultUser::LoadFile(String, UnityAction<StorageActionResult>)`（正确实现）：

```
ldarg.1
call     System.Boolean System.IO.Path::IsPathRooted(String)
brtrue.s  ...
ldsfld   System.String M4.Session.DefaultUser::PERSISTENT_DATA_PATH
ldarg.1
call     System.String System.String::Concat(String,String)
...
call     System.Boolean PajamaLlama.Utilities.IOUtility::TryReadAndDecompressAllBytes(String, Byte[]&)
```

`M4.Session.EpicUser::LoadFile(String, UnityAction<StorageActionResult>)`（**bug**）：

```
IL_0000: ldarg.1                                              // 原样使用 "PlayerSettings.json"
IL_0001: ldloca.s V_0
IL_0003: call  PajamaLlama.Utilities.IOUtility::TryReadAndDecompressAllBytes(String, Byte[]&)
```

缺少 `PERSISTENT_DATA_PATH` 前缀拼接 → 相对当前工作目录。

### 3.3 读取失败后的回调（触发默认值写入）

`Settings/<>c__DisplayClass25_0::<Load>b__0(StorageActionResult)`：

```
IL_0001: callvirt System.Boolean StorageActionResult::get_Succes()
IL_0006: brfalse.s IL_003c
   ... JsonUtility.FromJson<Settings>(...) ; Settings::set_Instance(...) ; (异常) Debug.LogWarning("Unable to load PlayerData: ")
IL_003C: ldsfld Settings Settings::s_instance
IL_0041: brtrue.s IL_0048
IL_0043: call   System.Void Settings::CreateInstance()      // 读失败 → 建默认实例
IL_0048: call   Settings Settings::get_Instance()
IL_004D: ldarg.0
IL_004E: ldfld  M4.Session.IUser Settings/<>c__DisplayClass25_0::user
IL_0053: stfld  M4.Session.IUser Settings::_user           // 注意：赋 _user 在 CreateInstance 之后
```

`Settings.CreateInstance()`：

```
new Settings()
AudioPlayerData  = new AudioPlayerData(true)
GameplayPlayerData = new GameplayPlayerData()
GraphicsPlayerData = new GraphicsPlayerData()
Settings::set_Instance(...)
Settings::ResetToDefaults()      // 内部最后调用 Save()
```

`Settings.ResetToDefaults()` 写出的值正好等于每次启动后文件里看到的内容：

| 字段 | 默认值 |
|---|---|
| MasterVolume / Music / UI / SFX | `0.8`（来自 `ApplicationSettings` 的 `_masterVolume`） |
| Rotation/Movement/ScrollingSensitivity | `0.5` |
| AutosaveLimit | `5` |
| ForceMouseAndKeyboard / Invert* | `false` |
| EdgeScrolling / ToggleGeneralStorageFilters / SnapBuilding / ShowBuildingGrid | `true` |
| UIScale | `1` |
| VSync | `true` |

## 4. 为什么之前的排查都没用

- **Epic 验证文件完整性**：只校验安装目录清单内文件，设置文件在 LocalLow，不在校验范围。
- **关闭云存档**：Flotsam 的 Epic 云同步覆盖的是 `Saves\` 下的 `.fs` 存档（日志可见其同步目录），不涉及设置文件。
- **管理员启动 / 清启动器缓存 / 删 `Saved\Saves\`**：都与该相对路径的解析无关。
- **Epic 日志里的 `isCorrupt: true`**：只是启动器对安装目录状态的标记，和 LocalLow 里的设置文件无关；
  而且该标记并不影响游戏读取设置。

## 5. 两种修复为什么有效

### 符号链接
在 `<GAME_DIR>\PlayerSettings.json` 建立指向 LocalLow 真实文件的符号链接：
- 读取（相对 CWD → `<GAME_DIR>\PlayerSettings.json`）→ 链接 → 真实文件 ✔
- 写入（绝对路径 → LocalLow 真实文件）→ 同一文件 ✔

### 程序集补丁
把 `Settings::Load` 中的 `ldstr "PlayerSettings.json"` 改成绝对路径：
- 读取直接命中 LocalLow 真实文件 ✔
- 写入不变（本来就是绝对路径）✔

两种方式都只影响「读取设置文件时使用的路径」，不改动存档、成就、在线功能。

## 6. 如何自行复核（可选）

游戏是 Mono 程序集，可以用 Mono.Cecil 直接读 IL：

```csharp
var asm = AssemblyDefinition.ReadAssembly("Assembly-CSharp.dll",
    new ReaderParameters { AssemblyResolver = new DefaultAssemblyResolver() });
var t = asm.MainModule.GetType("Settings");
var m = t.Methods.First(x => x.Name == "Load");
foreach (var ins in m.Body.Instructions)
    if (ins.OpCode == OpCodes.Ldstr) Console.WriteLine(ins.Operand);
// 输出: "PlayerSettings.json"  ← 应为绝对路径才是修复后状态
```

同样可以检查 `M4.Session.EpicUser::LoadFile` 与 `M4.Session.DefaultUser::LoadFile` 的差异。
