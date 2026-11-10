# Flotsam (Epic Games Store) — game settings reset on every launch: fix

> Applies to the **Epic Games Store** build of *Flotsam*.
>
> **Symptom**: every setting (master/music/UI/SFX volume, UI scale, VSync, language, mouse sensitivity,
> autosave limit, ...) is reset to defaults after restarting the game.
> `%USERPROFILE%\AppData\LocalLow\Pajama Llama Games\Flotsam\PlayerSettings.json` is rewritten with
> default values on every launch. **Save games (`.fs`) are not affected.**

## Root cause (game bug, not Epic)

Decompiling `Assembly-CSharp.dll` shows that **the settings are read from a different path than they are written to**:

- `Settings.Save()` → `EpicUser.SaveFile()` → writes to `Application.persistentDataPath`
  (`...\AppData\LocalLow\Pajama Llama Games\Flotsam\PlayerSettings.json`) — absolute path, correct.
- `Settings.Load()` → `EpicUser.LoadFile("PlayerSettings.json")` — **relative path**, resolved against the
  process working directory (the game install folder, e.g. `D:\Games\Flotsam`) → the file is never found.
- The other platform implementation (`DefaultUser.LoadFile()`) *does* prepend `Application.persistentDataPath`;
  the Epic one is missing that step.
- When loading fails, the game calls `CreateInstance()` → `ResetToDefaults()` → `Save()`, which immediately
  overwrites the real file in LocalLow with defaults.

That is why changing a setting updates the file, but restarting the game resets everything.

Epic's "Verify files", running as administrator, clearing the launcher cache, disabling cloud saves and deleting
`Saved\Saves\` cannot help: the file lives in LocalLow, outside the install folder and outside Epic's cloud-save
scope (Flotsam's Epic cloud save only covers `Saves\`).

## Fix (choose one)

### A. Symbolic link (recommended; does **not** modify game files)

Create a symlink named `PlayerSettings.json` in the game folder that points to the real file in LocalLow.
Requires administrator rights (or Windows Developer Mode).

```bat
mklink "<GAME_DIR>\PlayerSettings.json" "%USERPROFILE%\AppData\LocalLow\Pajama Llama Games\Flotsam\PlayerSettings.json"
```

Or run `tools\Fix-Settings-Symlink.bat` (self-elevates, finds the game, backs up the settings file).
Undo with `tools\Undo-Settings-Symlink.bat`.

### B. Assembly patch (no administrator rights needed)

Replace the `ldstr "PlayerSettings.json"` inside `Settings::Load()` with the absolute path.
Run `tools\Patch-Assembly.bat`: it locates the game, checks that it is not running, backs up the DLL
(`Assembly-CSharp.dll.original.bak-<timestamp>`) and verifies the patch by reading it back.
Undo with `tools\Restore-Assembly.bat`.

## Verify

Change a setting in-game, close the settings window, quit, relaunch — the setting should persist.
The file should keep your values instead of reverting to `"MasterVolume":0.8`, `"UIScale":1`, `"VSync":true`, ...
You will need to configure your settings once after applying the fix, because the current file contains defaults.

## Compatibility

- Tested with Epic build `1.0.1f9` (Unity `6000.3.26f1`).
- Original `Assembly-CSharp.dll` SHA256: `5B5C9F730ED71D5F66C0267064FC57667D2FF5644A018E9189B140CE025C1CD8`.
- The patcher finds the target by IL pattern, not by file hash, so other close versions usually work.

## Disclaimer

No game files are included. Patches are applied to your own legally installed copy.
Only the settings path bug is addressed; no DRM/anti-cheat/online functionality is touched.
Not affiliated with Pajama Llama Games or Epic Games. Use at your own risk.

## License

MIT for the scripts and documentation. `tools/lib/Mono.Cecil.dll` is MIT-licensed, see `tools/lib/NOTICE.txt`.

