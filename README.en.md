# Flotsam (Epic Games Store): settings reset — fix

**Problem**: settings in the Epic build of Flotsam are not saved after quitting — volume, language, UI scale,
VSync, sensitivity, autosave limit, etc. all revert to defaults after restarting the game.
`PlayerSettings.json` in `%USERPROFILE%\AppData\LocalLow\Pajama Llama Games\Flotsam\` is rewritten with defaults
on every launch. **Save games are not affected.**

**Nature**: a path bug in the Epic build itself — unrelated to Epic cloud saves, account permissions or a
corrupt install.

**Quick navigation**: Recommended solution · Alternative solution · Post-fix notes · Verification · Root cause · FAQ

---

## ✅ Recommended solution: symbolic link (TL;DR)

**Approach**: no game files are modified. A symlink named `PlayerSettings.json` is created in the game folder,
pointing to the real settings file, so that reads and writes resolve to the same file.

| Step | Action |
|---|---|
| 1 | Download this repository (`Code` → `Download ZIP`) and extract it |
| 2 | Run `tools\Fix-Settings-Symlink.bat` |
| 3 | Click "Yes" on the UAC prompt (the script requests administrator rights once) |

The script handles everything: locates the game folder → backs up the settings file → creates the symlink → verifies it.

**Manual command** (admin CMD):

```bat
mklink "<GAME_DIR>\PlayerSettings.json" "%USERPROFILE%\AppData\LocalLow\Pajama Llama Games\Flotsam\PlayerSettings.json"
```

**Requirements**: administrator rights, or Windows Developer Mode enabled.

**Rollback**: run `tools\Undo-Settings-Symlink.bat`, or delete `<GAME_DIR>\PlayerSettings.json`
(it is a link, not a game file).

---

## Alternative solution: assembly patch (no administrator rights needed)

**Approach**: replace the relative path used when reading settings with an absolute path — a single instruction
change, for environments where elevation is not possible.

| Step | Action |
|---|---|
| 1 | Download and extract this repository |
| 2 | Run `tools\Patch-Assembly.bat` |
| 3 | Confirm the prompt (the script shows the detected game version and file hash) |

The script handles everything: locates the game folder → checks that the game is not running → backs up the
original DLL → patches by IL pattern → verifies the result by reading it back.

**Rollback**: run `tools\Restore-Assembly.bat` (restores the newest backup).

> **Note**: a game update or Epic's "Verify files" restores the original DLL; run the script again afterwards.

---

## Post-fix notes

1. **Initial configuration**: the file currently contains only defaults; configure your settings once after
   applying the fix — changes will persist from then on.
2. **Epic "Verify / Repair"**: it reverts the assembly patch (the symlink is usually unaffected). If settings
   start resetting again, re-run the corresponding script.
3. **Game update / reinstall / moving the install folder**: the symlink may be gone → re-run
   `Fix-Settings-Symlink.bat`; the DLL patch is overwritten → re-run `Patch-Assembly.bat`.
4. **Scope**: neither method touches save games (`Saves\*.fs`), achievements or online features.

---

## Verification

| Step | Action |
|---|---|
| 1 | Open the in-game settings and change any option (e.g. master volume) |
| 2 | Close the settings window (this triggers saving) |
| 3 | Quit the game completely, then start it again |
| 4 | Check whether the setting persisted |

**File check**:

```bat
type "%USERPROFILE%\AppData\LocalLow\Pajama Llama Games\Flotsam\PlayerSettings.json"
```

**Expected result**: before the fix, the file reverts to defaults (`"MasterVolume":0.8`, `"UIScale":1`,
`"VSync":true`, ...) after every launch; after the fix, it keeps your values.

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

**Are save games affected?**
No. Saves use absolute paths and are not affected by this bug; neither method touches `Saves\`.

**Why don't "Verify files", disabling cloud saves or running as administrator help?**
The settings file lives in `%USERPROFILE%\AppData\LocalLow`, outside the install folder and outside Epic's
cloud-save scope (Flotsam's Epic cloud save only covers `Saves\`). None of those actions change the read path.

**Will Epic mark the install as corrupt?**
Files are not hash-checked at launch; only "Verify files" would revert the patch.

**Can the settings file simply be copied into the game folder?**
No. The game only reads from the working directory and only writes to LocalLow; a plain copy is stale on the
next launch. Both paths must point to the same file.

**Should cloud saves be disabled?**
Not necessary; they are unrelated.

---

## Disclaimer

- No game files are included; only scripts and documentation. Patches are applied to your own legally installed copy.
- Only the settings path bug is addressed; no DRM, anti-cheat, online or achievement functionality is touched.
- Not affiliated with Pajama Llama Games or Epic Games. Use at your own risk; back up the game folder first.
- If the developer ships an official fix, prefer it.

## License

Scripts and documentation: [MIT License](LICENSE).
`tools/lib/Mono.Cecil.dll` is a third-party MIT-licensed library, see [`tools/lib/NOTICE.txt`](tools/lib/NOTICE.txt).
