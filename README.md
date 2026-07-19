# ClearyDisplay

Windows display & font tuner with bilingual UI (中文 / English).

Adjust monitor brightness / contrast (DDC/CI), gamma ramp, ClearType, and brand-inspired presets (Apple, LG, Huawei, ASUS, Generic).

## Install

Download the latest **Setup** installer from [Releases](../../releases).

- Installs to `%LOCALAPPDATA%\ClearyDisplay` (no admin required)
- Optional desktop shortcut
- Optional “apply profile at logon”

## Run from source

```powershell
# Build EXE (requires ps2exe module)
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\Build-Release.ps1
```

Or open the GUI directly:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\src\GammaTuner.ps1
```

## Features

- Brightness / contrast via DDC/CI where supported
- Software gamma & scale (per session)
- ClearType smoothing controls + system wizard
- Brand recommendation chips with side panel details
- Power profiles (AC / battery)
- Named user presets
- Light / Dark / System UI theme
- ZH ↔ EN language toggle

## License

MIT
