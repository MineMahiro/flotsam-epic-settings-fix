# Changelog

## 1.0.0 — 2026-11-10

- 首次发布。
- 定位根因：Epic 版 Flotsam 的 `M4.Session.EpicUser.LoadFile()` 使用相对路径 `"PlayerSettings.json"`，
  而保存走 `Application.persistentDataPath`；读取失败后 `Settings` 会立即保存默认值覆盖真实文件。
- 提供两种修复方式：
  - 符号链接（不修改游戏文件，需要管理员权限）；
  - 程序集补丁（不需要管理员权限，只改一条 `ldstr` 指令）。
- 提供还原脚本与自动备份。
