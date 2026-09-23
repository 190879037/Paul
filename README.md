# ClearyDisplay

Windows display & font tuner with bilingual UI (中文 / English).
The in-app window title is **天选打工人专用小工具** ("the chosen worker's toolkit").

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
- **Type-in values**: every blue number (brightness / contrast / gamma / scale / font gamma / battery threshold) is directly editable — type a value and press Enter, the slider jumps to it and applies
- **Power card merged**: the AC/battery profile card now also hosts the low-battery plug-in reminder (both are power configuration)
- Low-battery reminder: popup when running on battery and the charge drops to a configurable threshold (default 73%), to avoid the black-screen / power-loss issue seen on worn batteries with an external monitor
- **Blackout report**: after an unexpected power-off (black screen), the next launch compares Windows shutdown/boot events (Kernel-Power 41, EventLog 6008, BugCheck 1001) and writes a local HTML report — including the charge level captured right before the outage — plus a one-click **黑屏报告 / Blackout report** button in the power card. Optional checkbox makes the app prompt you automatically after such a reboot.
- ClearType controls + system wizard
- Windows color calibration launcher
- Brand presets: Apple, LG, Huawei, ASUS, Samsung, Generic
- UI themes: GITHUB / Apple / DSA / Chrome, plus Light / Dark / System
- AC / battery profiles with ACLineStatus-based auto radio sync (does not auto-write screen brightness; click Apply to commit)
- Named presets; bilingual ZH / EN UI
- **Calculator tab**: Windows 11 style calculator layout (the `=` key is painted with the theme accent blue), plus a Bank of China FX board (**USD / EUR / GBP / JPY** — cash buying, cash selling and BOC converted rate) with one-click copy into a spreadsheet, and a number-to-English-words converter in foreign-trade document style (`SAY TOTAL USD ... ONLY`) with clipboard read
- **Image / cutout tab**: background removal as the main tool — seal/channel-threshold and solid-colour algorithms, automatic handling of dark backgrounds (including graded ones) via invert + local illumination normalisation, import by **drag-and-drop or click**, export as **transparent PNG** or **vector SVG**, and a side-by-side original/result preview
- New sliders inherit the app's thin-track slider style, and every numeric readout is type-in editable

## Build from source

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\Build-Release.ps1
```

## License

MIT