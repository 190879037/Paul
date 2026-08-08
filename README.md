# ClearyDisplay

Windows display & font tuner with bilingual UI (中文 / English).

## Install (another PC)

1. Download **ClearyDisplay-Setup-*.exe** from [Releases](https://github.com/stormertoolscn/ClearyDisplay/releases).
2. If Windows shows **SmartScreen** ("Windows protected your PC"):
   - Click **More info** → **Run anyway**
   - Or right-click the file → **Properties** → check **Unblock** → OK, then run again.
3. Install finishes to `%LOCALAPPDATA%\ClearyDisplay` (no admin required).

### Requirements

- Windows 10 / 11 (desktop / laptop with GUI)
- .NET Framework 4.x (usually already installed)
- Optional: monitor that supports **DDC/CI** for hardware brightness/contrast (otherwise gamma still works)

## Portable

You can also run `ClearyDisplay.exe` without the installer (same SmartScreen note).

## Features

- Brightness / contrast via DDC/CI where supported
- Software gamma & scale
- ClearType controls + system wizard
- Windows color calibration launcher
- Brand presets: Apple, LG, Huawei, ASUS, Samsung, Generic
- UI themes: GITHUB / Apple / DSA / Chrome, plus Light / Dark / System
- AC / battery profiles with ACLineStatus-based auto radio sync (does not auto-write screen brightness; click Apply to commit)
- Named presets; bilingual ZH / EN UI

## Build from source

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\Build-Release.ps1
```

## License

MIT