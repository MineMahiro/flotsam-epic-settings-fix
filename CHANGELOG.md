# Changelog

## 1.0.1 — 2026-11-11

- 增强路径探测：游戏目录优先读取 Epic 清单（支持任意盘符/目录），并增加常见布局扫描、一级目录扫描与
  `-InstallLocation` / `FLOTSAM_FIX_GAME_DIR` 手动指定；设置路径改用 Windows known folder API，兼容被重定向的用户目录。
- 程序集补丁 / 还原 / 撤销符号链接：检测安装目录是否可写，必要时自动请求管理员权限（覆盖 Program Files 安装）。
- 符号链接：可识别并替换悬空链接（目标已删除的旧链接）。
- 跳过 UNC 网络盘扫描，避免离线映射盘导致的长时间等待。
- 文档：补充路径探测顺序、多用户/换电脑说明与相关 FAQ（中英同步）。

## 1.0.0 — 2026-11-10

- 首次发布。
- 定位根因：Epic 版 Flotsam 的 `M4.Session.EpicUser.LoadFile()` 使用相对路径 `"PlayerSettings.json"`，
  而保存走 `Application.persistentDataPath`；读取失败后 `Settings` 会立即保存默认值覆盖真实文件。
- 提供两种修复方式：
  - 符号链接（不修改游戏文件，需要管理员权限）；
  - 程序集补丁（不需要管理员权限，只改一条 `ldstr` 指令）。
- 提供还原脚本与自动备份。
