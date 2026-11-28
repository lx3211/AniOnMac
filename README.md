# AniOnMac

[繁體中文](README.tw.md) | **English**

Convert Windows `.ani` animated cursors for macOS, preserving frame order, timing and hotspots.

## Usage

### Using the release

1. Download `AniOnMac-macOS-universal.zip` from GitHub Releases, extract it and open `AniOnMac.app`.
2. Create a theme and select a mode.
3. Choose an `.ani` file or drag it in.
4. Adjust size and hotspot, then select **Apply theme**.

- Note: [macOS security](https://support.apple.com/en-us/102445) may block the app when first opened.

  1. Go to **System Settings → Privacy & Security**.
  1. Click **Open Anyway**, then confirm by clicking **Open**.

### If the release cannot be opened

1. On GitHub, select **Code → Download ZIP** and extract the project.
2. Open Terminal, run the following command and finish installing the command-line tools (skip if already installed).

   ```sh
   xcode-select --install
   ```

3. Type `cd ` (with a trailing space), drag the extracted project folder into Terminal, then press Return.
4. Check that Python 3 is available. If the command is not found, install Python 3 from [python.org](https://www.python.org/downloads/macos/).

   ```sh
   python3 --version
   ```

5. Build the app.

   ```sh
   sh development/build.sh
   ```

6. Open the generated `AniOnMac.app` in the project root.
7. Continue with steps 2–4 under **Using the release** above.

## Features

| Mode | Purpose |
| --- | --- |
| Arrow | Normal cursor |
| Pointing | Hand over links or interactive controls, not a mouse-down state |
| IBeam | Text selection |
| Wait | System waiting cursor; macOS and applications decide when it appears |

1. Multiple custom themes, automatic saving and one-step undo
1. Live animation preview at 1:1 macOS points
1. Add an optional white outline to all imported cursors in a theme so they stand out on dark backgrounds. Use the dark preview to check the effect.
1. Independent settings for all four cursor modes
    - Per-mode size adjustment and reset
    - One-click size for the entire theme
1. Choose or drop an ANI file to preview it immediately
1. Drag or enter coordinates to adjust the hotspot; select **Use ANI default** to restore its original position
1. Imported ANI copies remain available after the original file moves
1. Chinese and English interfaces

## Compatibility and limitations

| Item | Status |
| --- | --- |
| Minimum build target | macOS 14 |
| Apple Silicon | Tested on macOS 26.6.2 hardware |
| Intel | Native x86_64 binary included; not tested on hardware |
| macOS 14 / 15 | Legacy cursor-name mapping included; not tested on hardware |
| macOS 26 and later | Uses ArrowS / IBeamS; future OS releases still require verification |

## Stored data

`~/Library/Application Support/AniOnMac/`

| Path | Contents |
| --- | --- |
| `library.json` | Themes, language and previous settings |
| `assets/` | Imported ANI copies |
| `previews/` | Animation preview frames |
| `backups/` | At most one system cursor backup per theme |
| `native-reset-recovery.cape` | Recovery file from before the latest native-appearance restoration |

Clearing a mode removes its theme reference without deleting the imported ANI copy.

## Repository layout

```text
AniOnMac/
├── AniOnMac.app/              # Locally built app; included in release ZIP
├── README.md                  # English documentation (default)
├── README.tw.md               # Traditional Chinese documentation
└── development/               # Source code and development tools
    ├── app/
    │   ├── Studio.swift       # Themes, storage, apply and undo
    │   └── Views.swift        # UI, drag-and-drop and animated previews
    ├── native/
    │   ├── ANIConverter.swift # ANI decoding, hotspot alignment and conversion
    │   ├── cursorctl.m        # System cursors, backups and verification
    │   ├── native_defaults.h  # Load native macOS cursors
    │   └── CursorRefresh.m    # Live refresh and button cursors
    ├── resources/             # Translations and app icon
    ├── tests/                 # Converter and apply-state tests
    ├── tools/                 # Icon generation tools
    ├── build.sh               # Build the Universal app
    ├── test.sh                # Run tests
    └── package.sh             # Package the release ZIP
```
