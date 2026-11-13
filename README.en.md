[日本語](README.md) | English

# Pixel Wave

A live wallpaper and screensaver where classic master paintings transition into one another in pixel art through expanding circular wave ripples.
Available as a desktop wallpaper and screensaver on Windows and macOS, and as a full-screen display on Linux. You can choose from 8 classic paintings or add your own images.

## Download & Installation

Download the package for your OS from the [Releases](https://github.com/mhota2021-cloud/pixel-wave/releases) page. Because the binaries are not signed with a paid code-signing certificate, your OS may show a security warning on the first launch. See the instructions below for each OS.

### Windows

- **File**: `PixelWaveSetup.exe` (Inno Setup installer; installs both the app and screensaver without administrator privileges)
- **Installation**: Run `PixelWaveSetup.exe` to install. You can enable the screensaver from the settings window inside the app.
- **Security Warning**: If Windows SmartScreen appears, click **More info** and then **Run anyway** (this happens because the binary is unsigned).

### macOS

- **File**: `PixelWave-macOS.dmg` (includes both the app and screensaver, Universal Binary for Apple Silicon and Intel)
- **Installation**: Open the DMG and drag **Pixel Wave.app** to the Applications folder. You can install the screensaver by clicking the screensaver option in the settings window.
- **Security Warning**: If Gatekeeper blocks the first launch, go to **System Settings** → **Privacy & Security** and click **Open Anyway** (macOS 15+ due to no notarization).

### Linux

- **Files**: `.AppImage` and `.deb` (for Ubuntu 24.04)
- **Installation**: For `.deb`, double-click or run `sudo apt install ./<filename>`. For `.AppImage`, grant execute permission (`chmod +x <filename>` or via file properties) and run.
- **Note**: Wallpaper and screensaver modes are not supported on Linux; use the **View Fullscreen** button in the settings window instead. Press any key or click to exit.

## Credits

The included paintings are public-domain works obtained from Wikimedia Commons. You can also view this list by clicking **Credits** at the bottom of the settings window.

- *The Great Wave off Kanagawa* (Katsushika Hokusai, c. 1830-1832)
- *The Starry Night* (Vincent van Gogh, 1889)
- *Bridge over a Pond of Water Lilies* (Claude Monet, 1899)
- *Liberty Leading the People* (Eugene Delacroix, 1830)
- *The Creation of Adam* (Michelangelo, c. 1508-1512)
- *The Birth of Venus* (Sandro Botticelli, c. 1484-1486)
- *The Scream* (Edvard Munch, 1893)
- *Girl with a Pearl Earring* (Johannes Vermeer, c. 1665)

Source URLs are listed in `assets/paintings/credits.json`.

## For Developers

- `win-ruby/`: Windows native version (Ruby + Windows GDI/WIC). See `win-ruby/README.md`.
- `engine/`: Rendering engine (TypeScript, Canvas 2D). See `engine/README.md`.
- `app/`: Tauri 2 application (macOS / Linux). See `app/README.md`.
- **Release Automation**: Pushing a version tag (e.g., `v0.1.0`) triggers GitHub Actions (`.github/workflows/release.yml`) to build and publish packages for all three OSes to Releases. Pull requests run tests across all three OSes (`.github/workflows/ci.yml`).
