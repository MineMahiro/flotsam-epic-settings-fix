# Flotsam (Epic Games Store): settings reset — fix

**Problem**: settings in the Epic build of Flotsam are not saved after quitting — volume, language, UI scale,
VSync, sensitivity, autosave limit, etc. all revert to defaults after restarting the game.
`PlayerSettings.json` in `%USERPROFILE%\AppData\LocalLow\Pajama Llama Games\Flotsam\` is rewritten with defaults
on every launch.

**Quick navigation**: Recommended solution · Alternative solution · Post-fix notes · Verification · Root cause · FAQ

---

## ✅ Recommended solution: symbolic link (TL;DR)

**Characteristics**: no game files are modified. A symlink named `PlayerSettings.json` is created in the game
folder, pointing to the real settings file, so that reads and writes resolve to the same file.

**✅ One-click fix**:

| Step | Action |
|---|---|
| 1 | Download this repository (`Code` → `Download ZIP`) and extract it |
| 2 | Run `tools\Fix-Settings-Symlink.bat` |
| 3 | Click "Yes" on the UAC prompt (the script requests administrator rights once) |

> The script handles everything: locates the game folder → backs up the settings file → creates the symlink → verifies it.

**Manual command method** (no need to download the repository):

| Step | Action |
|---|---|
| 1 | Open CMD as administrator |
| 2 | Replace `<GAME_DIR>` with your actual game folder, then run the command below |

```bat
mklink "<GAME_DIR>\PlayerSettings.json" "%USERPROFILE%\AppData\LocalLow\Pajama Llama Games\Flotsam\PlayerSettings.json"
```

**Rollback**: run `tools\Undo-Settings-Symlink.bat`, or delete `<GAME_DIR>\PlayerSettings.json`
(it is a link, not a game file).

---

## Alternative solution: assembly patch (no administrator rights needed)

**Characteristics**: replace the relative path used when reading settings with an absolute path — a single
instruction change, for environments where elevation is not possible.

| Step | Action |
|---|---|
| 1 | Download and extract this repository |
| 2 | Run `tools\Patch-Assembly.bat` |
| 3 | Confirm the prompt (the script shows the detected game version and file hash) |

> The script handles everything: locates the game folder → checks that the game is not running → backs up the
> original DLL → patches by IL pattern → verifies the result by reading it back.

**Rollback**: run `tools\Restore-Assembly.bat` (restores the newest backup).

---

## Post-fix notes

1. **Do not use Epic's integrity verification**  
   "Verify / Repair" reverts the assembly patch (the symlink is usually unaffected). If settings start resetting
   again, run the corresponding one-click script.

2. **Re-apply after a game update / reinstall / moving the install folder**  
   The symlink may be gone → re-run `Fix-Settings-Symlink.bat`; the DLL patch is overwritten → re-run `Patch-Assembly.bat`.

---

## Verification

| Step | Action |
|---|---|
| 1 | Open the in-game settings and change any option |
| 2 | Close the settings window (this triggers saving) |
| 3 | Quit the game completely, then start it again |
| 4 | Check whether the setting persisted |

**File check**:

```bat
type "%USERPROFILE%\AppData\LocalLow\Pajama Llama Games\Flotsam\PlayerSettings.json"
```

---

## Root cause

The Epic build resolves the "save" and "read" paths differently:

| Operation | Path | Result |
|---|---|---|
| Save `Settings.Save()` | `Application.persistentDataPath` (LocalLow, absolute) | works |
| Read `Settings.Load()` → `EpicUser.LoadFile()` | relative `"PlayerSettings.json"`, resolved against the process working directory (the install folder) | file not found, read fails |

On failure the game calls `CreateInstance()` → `ResetToDefaults()` → `Save()`, overwriting the real file in
LocalLow with defaults.

**Outcome**: changing a setting updates the file (write path is correct), but restarting the game overwrites it
with defaults. Save games use absolute paths, so they are unaffected.

Code-level details: [`docs/root-cause.md`](docs/root-cause.md)

---

## Compatibility

| Item | Value |
|---|---|
| Tested version | Epic build `1.0.1f9` (Unity `6000.3.26f1`) |
| Original `Assembly-CSharp.dll` SHA256 | `5B5C9F730ED71D5F66C0267064FC57667D2FF5644A018E9189B140CE025C1CD8` |

The patcher locates the target by IL pattern rather than a fixed file hash, so nearby versions usually work too;
unknown versions produce a warning. If a game update changes the code and the script reports "target not found",
use the symbolic link solution instead.

---

## FAQ

Q1: **Are save games affected?**  
A1: No. Saves use absolute paths and are not affected by this bug; neither method touches `Saves\`.

Q2: **Why don't "Verify files", disabling cloud saves or running as administrator help?**  
A2: The settings file lives in `%USERPROFILE%\AppData\LocalLow`, outside the install folder and outside Epic's
cloud-save scope (Flotsam's Epic cloud save only covers `Saves\`). None of those actions change the read path.

Q3: **Will Epic mark the install as corrupt?**  
A3: Files are not hash-checked at launch; only "Verify files" would revert the patch.

Q4: **Can the settings file simply be copied into the game folder?**  
A4: No. The game only reads from the working directory and only writes to LocalLow; a plain copy is stale on the
next launch. Both paths must point to the same file.

Q5: **Should cloud saves be disabled?**  
A5: Not necessary; they are unrelated.

---

## Disclaimer

- No game files are included; only scripts and documentation. Patches are applied to your own legally installed copy.
- Only the settings path bug is addressed; no DRM, anti-cheat, online or achievement functionality is touched.
- Not affiliated with Pajama Llama Games or Epic Games. Use at your own risk; back up the game folder first.
- If the developer ships an official fix, prefer it.

## License

Scripts and documentation: [MIT License](LICENSE).
`tools/lib/Mono.Cecil.dll` is a third-party MIT-licensed library, see [`tools/lib/NOTICE.txt`](tools/lib/NOTICE.txt).
