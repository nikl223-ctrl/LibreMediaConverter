# Windows Vision game → Android: technical port feasibility

Source: [Google Drive folder](https://drive.google.com/drive/folders/1ddUvXS4sHtkEt8-4Wi4sOofu3JmWWcYm)

## What the source actually contains

The Drive folder is an **installed Windows game**, not a development project.

Recognized entries include:

| File | Size | Purpose |
|---|---:|---|
| `bin9/rtws_app.exe` | 296,448 B | Windows executable (launcher) |
| `bin9/plugins/rtws_gamedll.vPlugin` | 1,001,472 B | Native game component |
| `bin9/Vision90.dll` | 1,376,768 B | Vision Engine Windows runtime |
| `data/city.v` | 452,795,096 B | Game data archive |
| `bin9/*.dll` | various | PhysX, FMOD and other legacy Windows dependencies |
| `redist/*` | various | Windows redistributables, DirectX setup, Visual C++ |

No engine editor project, source code, Android-compatible engine runtime or scene source was found in the inspected folder tree.

## Actual Windows workflow

[GitHub Actions: Windows Vision inspection](../../actions/workflows/windows-vision-audit.yml)

GitHub Actions triggers **windows-2022**. The worker runs only a PowerShell inspection script, authenticates to Google Drive using these *existing private OAuth secrets*:

- `GOOGLE_CLIENT_ID` (must belong to project `160241343420`)
- `GOOGLE_CLIENT_SECRET`
- `GOOGLE_REFRESH_TOKEN`

It requests these four files temporarily onto an **ephemeral Windows GitHub runner**:

`rtws_app.exe`, `rtws_gamedll.vPlugin`, `Vision90.dll`, `city.v`.

It computes SHA-256, checks source byte lengths, checks PE architecture if possible, and records the first 48 header bytes to infer `city.v`'s file format. It then **deletes** the local copies.

Only `Windows-Vision-Android-Port-Audit` (JSON metadata report) is uploaded to GitHub as an artifact. The Windows executable, original game DLLs and commercial data are **not uploaded to a public repository or workflow artifact**. This avoids accidental publication of game content whose ownership/redistribution rights are not verified.

## Why a direct APK is not possible with only these files

1. A Windows `.exe` / `.dll` cannot be converted into a native Android ARM64 APK by changing extension or using a GitHub runner.
2. The Windows engine and rendering/physics/audio stack are not the Android version of the engine.
3. Android porting a game at 1:1 fidelity requires the **original game source**, build files, the correct engine/toolchain, platform-specific changes, and compatible assets/licenses. If these are unavailable, this is a **new implementation**, not a faithful direct port.
4. `city.v` is a packed binary data file. It must be inspected and its extraction/usage rights established before integrating any content in an Android project.
5. The technical audit cannot determine legal rights to republish the game; proof of ownership or authorization should be obtained before publishing its binaries or original assets.

The prior Godot RPG project remains untouched; this audit exists on a standalone branch. The workflow does not run any untrusted EXE or installer on the Windows worker.

## Next input needed for a real 1:1 port

Please supply the original game **source code/engine project** and confirm you have permission to port and redistribute the game and its data. Otherwise, an independent Android reimplementation can be undertaken from documented gameplay, but it won't be a true 1:1 binary port.
