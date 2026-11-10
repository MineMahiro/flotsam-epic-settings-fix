# Flotsam（浮游世界）Epic 版「设置每次启动被重置」修复

> 适用于 **Epic Games Store 版** Flotsam / 浮游世界。
>
> **症状**：游戏里改的设置（主音量、音乐、UI 缩放、垂直同步、语言、鼠标灵敏度、自动存档数量等）
> 退出重进后全部回到默认值；`%USERPROFILE%\AppData\LocalLow\Pajama Llama Games\Flotsam\PlayerSettings.json`
> 每次启动都被改回默认内容。**游戏存档（`.fs`）不受影响。**

---

## 一、这是游戏自身的 bug，不是 Epic 云存档 / 权限 / 安装损坏

反编译 Epic 版游戏的 `Assembly-CSharp.dll` 后可以确认：设置「读取」和「保存」用的根本不是同一个路径。

| 操作 | 实际路径 |
|---|---|
| **保存** `Settings.Save()` → `EpicUser.SaveFile()` → `Application.persistentDataPath` | `%USERPROFILE%\AppData\LocalLow\Pajama Llama Games\Flotsam\PlayerSettings.json`（绝对路径，正确） |
| **读取** `Settings.Load()` → `EpicUser.LoadFile("PlayerSettings.json")` | 相对路径 → 相对**进程工作目录**（Epic 启动游戏时是游戏安装目录，如 `D:\Games\Flotsam`）→ **该文件不存在** |
| 对照：同程序里的 `DefaultUser.LoadFile()` | 会先拼 `Application.persistentDataPath` 前缀 —— **Epic 的实现漏了这一步** |

读取失败后，游戏会 `CreateInstance()` → `ResetToDefaults()` → `Save()`，
于是**立刻把默认值写回 LocalLow 里的真实文件**。

这解释了全部现象：

- 在游戏里改设置 → 文件确实变了（写路径正确）；
- 一重进 → 读不到 → 用默认值覆盖（看起来就像「设置被重置」）。

因此 Epic 的「验证文件完整性」「管理员启动」「清启动器缓存」「关闭云存档」「删除 `Saved\Saves`」都不会有用——
设置文件在 LocalLow，不在游戏安装目录，也不在 Epic 云同步范围内（Flotsam 的 Epic 云同步只覆盖 `Saves\` 下的存档）。

> 详细代码级分析见 [`docs/root-cause.md`](docs/root-cause.md)，机器上的实测证据见 [`docs/evidence.md`](docs/evidence.md)。

---

## 二、修复方法（二选一）

两种方法的共同原理：让「读」和「写」指向同一个文件。

### 方法 A：符号链接（推荐，**不修改游戏文件**）

在游戏安装目录里放一个 `PlayerSettings.json` 的符号链接，指向 LocalLow 里的真实文件。

需要 **管理员权限**（创建符号链接需要；或 Windows 设置里开启「开发者模式」）。

- 双击运行 [`tools/Fix-Settings-Symlink.bat`](tools/Fix-Settings-Symlink.bat)（会自动申请管理员权限，自动查找游戏目录、备份设置文件）
- 或者用管理员 CMD 手动执行：

```bat
mklink "<游戏目录>\PlayerSettings.json" "%USERPROFILE%\AppData\LocalLow\Pajama Llama Games\Flotsam\PlayerSettings.json"
```

撤销：运行 [`tools/Undo-Settings-Symlink.bat`](tools/Undo-Settings-Symlink.bat)。

### 方法 B：程序集补丁（**不需要管理员权限**）

把 `Settings::Load()` 里的字面量 `"PlayerSettings.json"` 改成绝对路径：

```
改前： IL_001A: ldstr "PlayerSettings.json"
改后： IL_001A: ldstr "%USERPROFILE%\AppData\LocalLow\Pajama Llama Games\Flotsam\PlayerSettings.json"
```

- 双击运行 [`tools/Patch-Assembly.bat`](tools/Patch-Assembly.bat)
- 脚本会：定位游戏目录 → 检查游戏是否在运行 → 备份原始 DLL → 按特征查找并打补丁 → 回读校验
- 备份文件：`Assembly-CSharp.dll.original.bak-<时间戳>`（与 DLL 同目录）

撤销：运行 [`tools/Restore-Assembly.bat`](tools/Restore-Assembly.bat)（恢复最近的备份）。

> 方法 B 本质上是「本地 mod」：只改一条读取路径，不碰存档、成就、在线功能。
> 游戏更新或点 Epic「验证文件完整性」后 DLL 会被还原，重新运行一次即可。

---

## 三、验证是否修好

1. 启动游戏，进入设置，改一项（例如主音量），关闭设置窗口（关闭时会触发保存）；
2. 完全退出游戏；
3. 重新进入游戏，检查该设置是否保留；
4. 也可以直接看文件：

```bat
dir "%USERPROFILE%\AppData\LocalLow\Pajama Llama Games\Flotsam\PlayerSettings.json"
type "%USERPROFILE%\AppData\LocalLow\Pajama Llama Games\Flotsam\PlayerSettings.json"
```

修复前：每次启动后文件会被改回默认值（例如 `"MasterVolume":0.8`、`"UIScale":1`、`"VSync":true`）；
修复后：文件内容应保持你设置的值。

> 修复后需要**重新设置一次**（修复前文件里只剩默认值）。

---

## 四、兼容性

| 项目 | 值 |
|---|---|
| 游戏版本（实测） | Epic build `1.0.1f9`（Unity `6000.3.26f1`） |
| 原始 `Assembly-CSharp.dll` SHA256 | `5B5C9F730ED71D5F66C0267064FC57667D2FF5644A018E9189B140CE025C1CD8` |
| 补丁后 SHA256（仅作参考） | `D089853629F591BD3D167A7914ABB670A0FD4CB45DA5154B9A6015E43B874F24` |

补丁脚本按 **IL 特征** 查找（`Settings::Load` 中对 `"PlayerSettings.json"` 的 `ldstr`），
不硬编码文件哈希，因此对其它相近版本通常也适用；遇到未知版本会提示，但仍可尝试。

如果游戏更新后代码结构变化、脚本报告「未找到目标方法」，请用方法 A（符号链接）。

---

## 五、FAQ

**Q：会影响存档吗？**
A：不会。存档读写用的是绝对的存档目录，没有这个 bug；两种修复都不触碰 `Saves\`。

**Q：会被 Epic 判定为「安装损坏」吗？**
A：Epic 启动游戏时不会校验文件哈希；不点「验证文件完整性」就不会触发。即使被还原，重新运行补丁即可。

**Q：为什么官方不修？**
A：这是 Epic 平台适配分支里的路径处理遗漏；Steam 等平台走的是另一套 `Platform` 实现，通常没有该问题。
建议向 Pajama Llama Games 反馈，附上本文档的代码分析。

**Q：为什么不能直接把设置文件放到游戏目录？**
A：游戏**只从**工作目录读，但**只往** LocalLow 写；普通副本还是会在下次启动时读到旧值。
必须让两个路径指向同一个文件（符号链接 / 符号链接式补丁）。

**Q：云存档要不要关？**
A：不需要关。Flotsam 的 Epic 云同步只同步 `Saves\` 存档，和设置文件无关。

---

## 六、免责声明

- 本仓库**不包含任何游戏文件**，只包含脚本和文档；补丁在你本机合法安装的游戏副本上执行。
- 仅用于修复上述设置读写路径问题，不涉及 DRM、破解、在线作弊或成就修改。
- 与 Pajama Llama Games、Epic Games 无关。使用风险自负，建议先备份游戏目录。
- 如果官方发布了修复，请优先使用官方版本。

## 七、License

本仓库的脚本与文档采用 [MIT License](LICENSE)。
`tools/lib/Mono.Cecil.dll` 为第三方 MIT 许可库，见 [`tools/lib/NOTICE.txt`](tools/lib/NOTICE.txt)。

