# Flotsam（浮游世界）Epic 版：设置重置问题修复

**问题**：Epic 版 Flotsam 的游戏设置在退出后不保存——音量、语言、UI 缩放、垂直同步、灵敏度、自动存档数量等改动，
重进游戏后全部恢复默认；`%USERPROFILE%\AppData\LocalLow\Pajama Llama Games\Flotsam\PlayerSettings.json`
每次启动都会被改回默认内容。

**快速导航**：推荐方案 · 备选方案 · 修复后注意事项 · 验证方法 · 原因分析 · 常见问题

---

## ✅ 推荐方案：符号链接（TL;DR）

**方案特点**：不修改任何游戏文件，仅在游戏目录创建一个指向真实设置文件的符号链接，使设置的读取与写入落在同一文件。

**✅ 一键修复方法**：

| 步骤 | 操作 |
|---|---|
| 1 | 下载本仓库（`Code` → `Download ZIP`）并解压 |
| 2 | 双击运行 `tools\Fix-Settings-Symlink.bat` |
| 3 | 在 UAC 提示中点击「是」（脚本会请求一次管理员权限） |

> 脚本自动完成：定位游戏目录 → 备份设置文件 → 创建符号链接 → 校验可读性。

**手输命令方法**（无需下载仓库的平替方案）：

| 步骤 | 操作 |
|---|---|
| 1 | 以管理员模式打开CMD |
| 2 | 将<游戏目录>替换为你的真实游戏目录后执行下列命令 |

```bat
mklink "<游戏目录>\PlayerSettings.json" "%USERPROFILE%\AppData\LocalLow\Pajama Llama Games\Flotsam\PlayerSettings.json"
```

**回退方法**：运行 `tools\Undo-Settings-Symlink.bat`，或删除游戏目录下的 `PlayerSettings.json`（该文件为链接，不是游戏文件）。

---

## 备选方案：程序集补丁（一般无需管理员权限）

**方案特点**：将游戏读取设置时使用的相对路径改为绝对路径，仅改动一条指令；适用于无法提权的环境。  
若游戏安装在 `Program Files` 等不可写目录，脚本会自动请求一次管理员权限。

| 步骤 | 操作 |
|---|---|
| 1 | 下载并解压本仓库 |
| 2 | 双击运行 `tools\Patch-Assembly.bat` |
| 3 | 按提示确认（脚本会显示检测到的游戏版本与文件哈希） |

> 脚本自动完成：定位游戏目录 → 检查游戏未运行 → 备份原始 DLL → 按 IL 特征打补丁 → 回读校验。

**回退方法**：运行 `tools\Restore-Assembly.bat`（恢复最近一次备份）。

---

## 修复后注意事项

1. **不要使用Epic的完整性验证**  
   「验证文件完整性 / 修复」会还原程序集补丁（对符号链接一般无影响）。若设置重新出现重置，运行对应方案的一键脚本即可。

2. **游戏更新 / 重装 / 移动安装目录时需重新修复**  
   符号链接可能丢失 → 重跑 `Fix-Settings-Symlink.bat`；程序集补丁会被覆盖 → 重跑 `Patch-Assembly.bat`。

3. **多个 Windows 账户 / 更换电脑时按账户重新运行**  
   设置路径属于当前 Windows 用户，脚本按运行时的账户计算路径；共用一台电脑的多个账户需各自运行一次。

---

## 验证方法

| 步骤 | 操作 |
|---|---|
| 1 | 进入游戏设置，修改任意一项 |
| 2 | 关闭设置窗口（关闭时触发保存） |
| 3 | 完全退出游戏后重新进入 |
| 4 | 检查该设置是否保留 |

**文件检查方式**：

```bat
type "%USERPROFILE%\AppData\LocalLow\Pajama Llama Games\Flotsam\PlayerSettings.json"
```

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

**路径探测方式**：

| 目标 | 探测顺序 |
|---|---|
| 游戏目录 | Epic 启动器清单（读取 `InstallLocation`）→ 本地磁盘常见布局扫描 → `-InstallLocation` 参数 / `FLOTSAM_FIX_GAME_DIR` 环境变量 |
| 设置文件 | 当前用户的 LocalLow（Windows known folder API，兼容被重定向的用户目录） |

补丁写入的是「运行脚本时那台电脑、那个 Windows 用户」的绝对路径，因此在任何电脑上打补丁都会指向该机的正确位置。

自动定位失败时，可手动指定安装目录：

```powershell
powershell -ExecutionPolicy Bypass -File tools\Patch-Assembly.ps1 -InstallLocation "D:\Games\Flotsam"
```

---

## 常见问题

Q1: **存档是否受影响？**  
A1: 不受影响。存档读写使用绝对路径，不存在该缺陷；两种方案均不触碰 `Saves\`。

Q2: **「验证文件完整性」「关闭云存档」「管理员启动」为何无效？**  
A2: 设置文件位于 `%USERPROFILE%\AppData\LocalLow`，不在游戏安装目录，也不在 Epic 云同步范围内
（Flotsam 的 Epic 云同步仅覆盖 `Saves\`）。上述操作均不会改变游戏的读取路径。

Q3: **是否会被 Epic 判定为安装损坏？**  
A3: 启动游戏时不会校验文件哈希；不使用「验证文件完整性」即不会触发。

Q4: **能否直接将设置文件复制到游戏目录？**  
A4: 不能。游戏仅从工作目录读取、仅向 LocalLow 写入，普通副本会在下次启动时被当作旧值。两个路径必须指向同一文件。

Q5: **是否需要关闭云存档？**  
A5: 不需要，二者无关。

Q6: **换一台电脑、游戏装在别的盘，还能用吗？**  
A6: 能。游戏目录优先从 Epic 启动器清单读取，与盘符和目录名无关；设置文件按本机当前用户计算；补丁在目标机上生成该机的绝对路径。自动定位失败时可用 `-InstallLocation` 指定。

Q7: **游戏安装在 Program Files，脚本报「访问被拒绝」怎么办？**  
A7: 新版脚本检测到安装目录不可写时会自动请求管理员权限；也可右键对应 `.bat` 选择「以管理员身份运行」。

---

## 免责声明

- 本仓库不包含任何游戏文件，仅包含脚本与文档；补丁作用于本机合法安装的游戏副本。
- 仅用于修复上述设置读写路径问题，不涉及 DRM、破解、在线作弊或成就修改。
- 与 Pajama Llama Games、Epic Games 无关；使用风险自负，建议提前备份游戏目录。
- 若官方已发布修复，请优先使用官方版本。

## License

脚本与文档采用 [MIT License](LICENSE)。
`tools/lib/Mono.Cecil.dll` 为第三方 MIT 许可库，详见 [`tools/lib/NOTICE.txt`](tools/lib/NOTICE.txt)。
