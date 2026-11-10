# Flotsam（浮游世界）Epic 版：设置重置问题修复

**问题**：Epic 版 Flotsam 的游戏设置在退出后不保存——音量、语言、UI 缩放、垂直同步、灵敏度、自动存档数量等改动，
重进游戏后全部恢复默认；`%USERPROFILE%\AppData\LocalLow\Pajama Llama Games\Flotsam\PlayerSettings.json`
每次启动都会被改回默认内容。**游戏存档不受影响。**

**性质**：Epic 版游戏自身的路径缺陷，与 Epic 云存档、账户权限、安装完整性无关。

**快速导航**：推荐方案 · 备选方案 · 修复后注意事项 · 验证方法 · 原因分析 · 常见问题

---

## ✅ 推荐方案：符号链接（TL;DR）

**方案要点**：不修改任何游戏文件，仅在游戏目录创建一个指向真实设置文件的符号链接，使设置的读取与写入落在同一文件。

| 步骤 | 操作 |
|---|---|
| 1 | 下载本仓库（`Code` → `Download ZIP`）并解压 |
| 2 | 双击运行 `tools\Fix-Settings-Symlink.bat` |
| 3 | 在 UAC 提示中点击「是」（脚本会请求一次管理员权限） |

脚本自动完成：定位游戏目录 → 备份设置文件 → 创建符号链接 → 校验可读性。

**手动命令**（管理员 CMD）：

```bat
mklink "<游戏目录>\PlayerSettings.json" "%USERPROFILE%\AppData\LocalLow\Pajama Llama Games\Flotsam\PlayerSettings.json"
```

**权限要求**：管理员权限；或在 Windows 设置中开启「开发者模式」后直接执行。

**撤销方式**：运行 `tools\Undo-Settings-Symlink.bat`，或删除游戏目录下的 `PlayerSettings.json`（该文件为链接，不是游戏文件）。

---

## 备选方案：程序集补丁（不需要管理员权限）

**方案要点**：将游戏读取设置时使用的相对路径改为绝对路径，仅改动一条指令；适用于无法提权的环境。

| 步骤 | 操作 |
|---|---|
| 1 | 下载并解压本仓库 |
| 2 | 双击运行 `tools\Patch-Assembly.bat` |
| 3 | 按提示确认（脚本会显示检测到的游戏版本与文件哈希） |

脚本自动完成：定位游戏目录 → 检查游戏未运行 → 备份原始 DLL → 按 IL 特征打补丁 → 回读校验。

**撤销方式**：运行 `tools\Restore-Assembly.bat`（恢复最近一次备份）。

> **注意**：游戏更新或使用 Epic「验证文件完整性」后，DLL 会被还原；重新运行一次本脚本即可。

---

## 修复后注意事项

1. **首次设置**：修复前文件内仅剩默认值，修复后需按个人偏好重新设置一次；此后设置会正常保存。
2. **Epic 验证功能**：「验证文件完整性 / 修复」会还原程序集补丁（对符号链接一般无影响）。若设置重新出现重置，运行对应方案的一键脚本即可。
3. **游戏更新 / 重装 / 移动安装目录**：符号链接可能丢失 → 重跑 `Fix-Settings-Symlink.bat`；程序集补丁会被覆盖 → 重跑 `Patch-Assembly.bat`。
4. **影响范围**：两种方案均不影响存档（`Saves\*.fs`）、成就与在线功能。

---

## 验证方法

| 步骤 | 操作 |
|---|---|
| 1 | 进入游戏设置，修改任意一项（例如主音量） |
| 2 | 关闭设置窗口（关闭时触发保存） |
| 3 | 完全退出游戏后重新进入 |
| 4 | 检查该设置是否保留 |

**文件检查方式**：

```bat
type "%USERPROFILE%\AppData\LocalLow\Pajama Llama Games\Flotsam\PlayerSettings.json"
```

**判断标准**：修复前，每次启动后文件都会恢复默认值（`"MasterVolume":0.8`、`"UIScale":1`、`"VSync":true` 等）；
修复后，文件内容应保持为你的设置值。

---

## 原因分析

Epic 版游戏中，设置的「保存」与「读取」使用了不同的路径解析方式：

| 操作 | 路径 | 结果 |
|---|---|---|
| 保存 `Settings.Save()` | `Application.persistentDataPath`（LocalLow，绝对路径） | 正常 |
| 读取 `Settings.Load()` → `EpicUser.LoadFile()` | 相对路径 `"PlayerSettings.json"`，相对游戏进程工作目录（安装目录） | 文件不存在，读取失败 |

读取失败后，游戏执行 `CreateInstance()` → `ResetToDefaults()` → `Save()`，用默认值覆盖 LocalLow 中的真实文件。

**结果**：游戏内修改设置时文件会正常更新；重新启动时因读取失败而被默认值覆盖，表现为「设置每次重置」。
存档使用绝对路径，因此不受影响。

代码级细节：[`docs/root-cause.md`](docs/root-cause.md)

---

## 兼容性

| 项目 | 值 |
|---|---|
| 实测版本 | Epic build `1.0.1f9`（Unity `6000.3.26f1`） |
| 原始 `Assembly-CSharp.dll` SHA256 | `5B5C9F730ED71D5F66C0267064FC57667D2FF5644A018E9189B140CE025C1CD8` |

补丁脚本按 IL 特征定位目标，不依赖固定文件哈希，相近版本通常同样适用；未知版本会给出提示。
若游戏更新后脚本报告「未找到目标方法」，请改用符号链接方案。

---

## 常见问题

**存档是否受影响？**
不受影响。存档读写使用绝对路径，不存在该缺陷；两种方案均不触碰 `Saves\`。

**「验证文件完整性」「关闭云存档」「管理员启动」为何无效？**
设置文件位于 `%USERPROFILE%\AppData\LocalLow`，不在游戏安装目录，也不在 Epic 云同步范围内
（Flotsam 的 Epic 云同步仅覆盖 `Saves\`）。上述操作均不会改变游戏的读取路径。

**是否会被 Epic 判定为安装损坏？**
启动游戏时不会校验文件哈希；不使用「验证文件完整性」即不会触发。

**能否直接将设置文件复制到游戏目录？**
不能。游戏仅从工作目录读取、仅向 LocalLow 写入，普通副本会在下次启动时被当作旧值。两个路径必须指向同一文件。

**是否需要关闭云存档？**
不需要，二者无关。

---

## 免责声明

- 本仓库不包含任何游戏文件，仅包含脚本与文档；补丁作用于本机合法安装的游戏副本。
- 仅用于修复上述设置读写路径问题，不涉及 DRM、破解、在线作弊或成就修改。
- 与 Pajama Llama Games、Epic Games 无关；使用风险自负，建议提前备份游戏目录。
- 若官方已发布修复，请优先使用官方版本。

## License

脚本与文档采用 [MIT License](LICENSE)。
`tools/lib/Mono.Cecil.dll` 为第三方 MIT 许可库，详见 [`tools/lib/NOTICE.txt`](tools/lib/NOTICE.txt)。
