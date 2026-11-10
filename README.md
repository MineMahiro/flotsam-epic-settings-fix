# Flotsam（浮游世界）Epic 版：设置每次启动被重置 · 修复

> **症状**：Epic 版 Flotsam 里改过的设置（音量、语言、UI 缩放、垂直同步、灵敏度、自动存档数量等），
> 退出重进后全部恢复默认；`%USERPROFILE%\AppData\LocalLow\Pajama Llama Games\Flotsam\PlayerSettings.json`
> 每次启动都会被改回默认内容。**游戏存档不受影响。**
>
> 这是 Epic 版游戏自身的路径 bug，不是 Epic 云存档或安装损坏。

---

## ✅ 推荐方案：符号链接（TL;DR）

**不修改游戏文件**，只需在游戏安装目录放一个指向真实设置文件的符号链接。

**一键脚本**：下载本仓库 → 双击运行 [`tools/Fix-Settings-Symlink.bat`](tools/Fix-Settings-Symlink.bat)
（会请求一次管理员权限；自动定位游戏目录、备份设置文件、创建链接并校验）。

**手动命令**（管理员 CMD）：

```bat
mklink "<游戏目录>\PlayerSettings.json" "%USERPROFILE%\AppData\LocalLow\Pajama Llama Games\Flotsam\PlayerSettings.json"
```

> 需要管理员权限；也可在 Windows 设置中开启「开发者模式」后免提权执行。

**撤销**：运行 [`tools/Undo-Settings-Symlink.bat`](tools/Undo-Settings-Symlink.bat)，或直接删除游戏目录下的
`PlayerSettings.json`（它是链接，不是游戏文件）。

---

## 备选方案：程序集补丁（不需要管理员权限）

无法提权时使用：把游戏读取设置用的相对路径改成绝对路径，只改一条指令。

- 双击 [`tools/Patch-Assembly.bat`](tools/Patch-Assembly.bat)：自动定位游戏、检查游戏未运行、
  备份原始 DLL、按 IL 特征打补丁并回读校验。
- 撤销：[`tools/Restore-Assembly.bat`](tools/Restore-Assembly.bat)（恢复最近的备份）。

> 游戏更新或点 Epic「验证文件完整性」会还原 DLL，重新运行一次即可。

---

## 修复后注意事项

1. **需要重新设置一次**：修复前文件里只剩默认值，改完后会正常保存。
2. **不要点 Epic 的「验证文件完整性 / 修复」**：它会还原程序集补丁（符号链接一般不受影响）。
   若发现设置又开始重置，重新运行对应的一键脚本即可。
3. **游戏更新 / 重装 / 移动安装目录后**：符号链接可能丢失 → 重跑 `Fix-Settings-Symlink.bat`；
   程序集补丁会被覆盖 → 重跑 `Patch-Assembly.bat`。
4. 两种方法都**不影响存档（`Saves\*.fs`）、成就和在线功能**。

---

## 验证方法

1. 进入游戏设置，改一项（如主音量），关闭设置窗口（关闭时会触发保存）；
2. 完全退出游戏，再重新进入；
3. 设置应保留。也可直接查看文件：

```bat
type "%USERPROFILE%\AppData\LocalLow\Pajama Llama Games\Flotsam\PlayerSettings.json"
```

修复前每次启动后文件都会变回默认值（`"MasterVolume":0.8`、`"UIScale":1`、`"VSync":true` 等）；
修复后应保持你设置的值。

---

## 原因分析

反编译确认：Epic 版中「保存」和「读取」设置用的不是同一个路径。

- **保存**：`Settings.Save()` → 写入 `Application.persistentDataPath`
  （`...\AppData\LocalLow\Pajama Llama Games\Flotsam\PlayerSettings.json`，绝对路径，正确）；
- **读取**：`Settings.Load()` → `EpicUser.LoadFile("PlayerSettings.json")` 使用**相对路径**，
  相对的是游戏进程的工作目录（游戏安装目录）→ 该文件不存在；
- 读取失败后，游戏立即 `CreateInstance()` → `ResetToDefaults()` → `Save()`，
  用默认值覆盖 LocalLow 里的真实文件。

因此表现为「改设置时文件会变，一重进就变回默认」。存档使用绝对路径，所以不受影响。

代码级细节见 [`docs/root-cause.md`](docs/root-cause.md)。

---

## 兼容性

| 项目 | 值 |
|---|---|
| 实测版本 | Epic build `1.0.1f9`（Unity `6000.3.26f1`） |
| 原始 `Assembly-CSharp.dll` SHA256 | `5B5C9F730ED71D5F66C0267064FC57667D2FF5644A018E9189B140CE025C1CD8` |

补丁脚本按 IL 特征查找，不硬编码文件哈希，相近版本通常也适用；遇到未知版本会给出提示。
若游戏更新后脚本报告「未找到目标方法」，请改用符号链接方式。

---

## FAQ

**会影响存档吗？**
不会。存档读写使用绝对路径，没有这个 bug；两种修复都不触碰 `Saves\`。

**为什么「验证文件完整性」「关云存档」「管理员启动」都没用？**
设置文件在 `%USERPROFILE%\AppData\LocalLow`，不在游戏安装目录，也不在 Epic 云同步范围内
（Flotsam 的 Epic 云同步只覆盖 `Saves\`）。这些操作都改变不了游戏的读取路径。

**会被 Epic 判定为安装损坏吗？**
启动游戏时不会校验文件；不点「验证文件完整性」就不会触发。

**为什么不能直接把设置文件复制到游戏目录？**
游戏只从工作目录读、只往 LocalLow 写；复制一份普通文件，下次启动还是会读到旧值。
必须让两个路径指向同一个文件。

**需要关闭云存档吗？**
不需要，与设置文件无关。

---

## 免责声明

- 本仓库不包含任何游戏文件，只包含脚本和文档；补丁作用于你本机合法安装的游戏副本。
- 仅用于修复上述设置读写路径问题，不涉及 DRM、破解、在线作弊或成就修改。
- 与 Pajama Llama Games、Epic Games 无关；使用风险自负，建议先备份游戏目录。
- 如果官方已发布修复，请优先使用官方版本。

## License

脚本与文档采用 [MIT License](LICENSE)。
`tools/lib/Mono.Cecil.dll` 为第三方 MIT 许可库，见 [`tools/lib/NOTICE.txt`](tools/lib/NOTICE.txt)。
