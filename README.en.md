# Flotsam (Epic Games Store): settings reset on every launch — fix

> **Symptom**: settings changed in-game (volume, language, UI scale, VSync, sensitivity, autosave limit, ...)
> revert to defaults after restarting the game; `PlayerSettings.json` in
> `%USERPROFILE%\AppData\LocalLow\Pajama Llama Games\Flotsam\` is rewritten with defaults on every launch.
> **Save games are not affected.**
>
> This is a path bug in the Epic build of the game — not Epic cloud saves, permissions or a corrupt install.

---

## ✅ Recommended fix: symbolic link (TL;DR)

**No game files are modified.** Put a symlink named `PlayerSettings.json` in the game folder that points to
the real settings file.

**One-click script**: download this repo and run [`tools/Fix-Settings-Symlink.bat`](tools/Fix-Settings-Symlink.bat)
(asks for administrator rights once; locates the game, backs up the settings file, creates the link and verifies it).

**Manual command** (admin CMD):

```bat
mklink "<GAME_DIR>\PlayerSettings.json" "%USERPROFILE%\AppData\LocalLow\Pajama Llama Games\Flotsam\PlayerSettings.json"
```

> Requires administrator rights (or Windows Developer Mode).

**Undo**: [`tools/Undo-Settings-Symlink.bat`](tools/Undo-Settings-Symlink.bat), or just delete
`<GAME_DIR>\PlayerSettings.json` (it is a link, not a game file).

---

## Alternative fix: assembly patch (no administrator rights needed)

Use this if you cannot elevate. It replaces one string literal so the game reads the settings via an absolute path.

- Run [`tools/Patch-Assembly.bat`](tools/Patch-Assembly.bat): locates the game, checks that it is not running,
  backs up the original DLL, patches by IL pattern and verifies the result by reading it back.
- Undo: [`tools/Restore-Assembly.bat`](tools/Restore-Assembly.bat) (restores the newest backup).

> A game update or Epic's "Verify files" restores the original DLL; run the script again afterwards.

---

## After applying the fix

1. **Configure your settings once** — the current file only contains defaults; changes will persist from now on.
2. **Do not use Epic's "Verify / Repair"** — it reverts the assembly patch (the symlink is usually unaffected).
   If settings start resetting again, re-run the corresponding script.
3. **After a game update / reinstall / moving the game folder**: re-run `Fix-Settings-Symlink.bat`
   (symlink may be gone) or `Patch-Assembly.bat` (DLL overwritten).
4. Neither method touches save games (`Saves\*.fs`), achievements or online features.

---

## Verify it works

1. Change a setting in-game, close the settings window (saving is triggered on close);
2. Quit the game completely and start it again;
3. The setting should persist. You can also inspect the file directly:

```bat
type "%USERPROFILE%\AppData\LocalLow\Pajama Llama Games\Flotsam\PlayerSettings.json"
```

Before the fix the file reverted to defaults (`"MasterVolume":0.8`, `"UIScale":1`, `"VSync":true`, ...)
after every launch; after the fix it should keep your values.

---

## Root cause

The Epic build **reads and writes settings using different paths**:

- **Write**: `Settings.Save()` → `Application.persistentDataPath`
  (`...\AppData\LocalLow\Pajama Llama Games\Flotsam\PlayerSettings.json`) — absolute, correct.
- **Read**: `Settings.Load()` → `EpicUser.LoadFile("PlayerSettings.json")` — a **relative** path, resolved against
  the process working directory (the game install folder) → the file is never found.
- On failure the game immediately calls `CreateInstance()` → `ResetToDefaults()` → `Save()`, overwriting the real
  file in LocalLow with defaults.

That is why changing a setting updates the file, but restarting resets everything. Save games use absolute paths,
so they are unaffected. Code-level details: [`docs/root-cause.md`](docs/root-cause.md).

---

## Compatibility

| Item | Value |
|---|---|
| Tested version | Epic build `1.0.1f9` (Unity `6000.3.26f1`) |
| Original `Assembly-CSharp.dll` SHA256 | `5B5C9F730ED71D5F66C0267064FC57667D2FF5644A018E9189B140CE025C1CD8` |

The patcher finds the target by IL pattern, not by file hash, so nearby versions usually work.
If the game update changes the code and the script reports "target not found", use the symlink method.

---

## FAQ

**Does it affect save games?** No. Saves use absolute paths and are not affected by this bug.

**Why didn't "Verify files", disabling cloud saves or running as administrator help?**
The settings file lives in `%USERPROFILE%\AppData\LocalLow`, outside the install folder and outside Epic's
cloud-save scope (Flotsam's Epic cloud save only covers `Saves\`). None of those actions change the read path.

**Will Epic mark the install as corrupt?** Files are not hash-checked at launch; only "Verify files" would revert
the patch.

**Why can't I just copy the settings file into the game folder?** The game only reads from the working directory
and only writes to LocalLow; a plain copy is stale on the next launch. Both paths must point to the same file.

**Should I disable cloud saves?** Not necessary; unrelated to settings.

---

## Disclaimer

- No game files are included; the scripts patch your own legally installed copy.
- Only the settings path bug is addressed; no DRM, anti-cheat, online or achievement functionality is touched.
- Not affiliated with Pajama Llama Games or Epic Games. Use at your own risk; back up the game folder first.
- If the developer ships an official fix, prefer it.

## License

Scripts and documentation: [MIT License](LICENSE).
`tools/lib/Mono.Cecil.dll` is a third-party MIT-licensed library, see [`tools/lib/NOTICE.txt`](tools/lib/NOTICE.txt).
