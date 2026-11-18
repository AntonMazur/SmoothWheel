# Install SmoothWheel

The current download is for **Apple Silicon Macs running macOS 13 or later**. It is free and MIT licensed. Accessibility permission is required. The current build is ad-hoc signed and **not notarized**.

## With Homebrew

If you already use [Homebrew](https://brew.sh), run:

```sh
brew install --cask antonmazur/tap/smoothwheel
```

This uses the [developer-maintained tap](https://github.com/AntonMazur/homebrew-tap), which downloads the versioned GitHub release and checks its SHA-256 checksum. It is separate from the official Homebrew Cask catalog. Homebrew has its own [macOS requirements](https://docs.brew.sh/Installation#macos-requirements).

Already installed by dragging the app to Applications? Quit SmoothWheel from its menu-bar menu and move your existing **SmoothWheel.app** from Applications to the Trash before running the command. This preserves your preferences. Avoid keeping multiple copies of the app in different folders.

## Without Homebrew

1. [Download SmoothWheel.zip](https://github.com/AntonMazur/SmoothWheel/releases/latest/download/SmoothWheel.zip).
2. Double-click the ZIP to extract it.
3. Drag **SmoothWheel.app** into **Applications**, then open that copy.

## First launch

1. Try opening **SmoothWheel** from Applications. Since this build is not notarized, macOS may block the initial launch. If you trust the download and macOS offers **Open Anyway**, you can approve it in **System Settings → Privacy & Security** after attempting to open the app. See [Apple's explanation](https://support.apple.com/en-us/102445). Do not proceed if macOS reports malware or a damaged app; report the exact message instead.
2. Grant SmoothWheel access in **System Settings → Privacy & Security → Accessibility**. The app needs this permission to process mouse-wheel events.
3. In SmoothWheel, turn on **Enable smoothing** and start with **Balanced**. Try scrolling in the built-in **Playground** before adjusting speed and smoothing.

Smoothing starts **disabled on every launch**. Closing the settings window keeps the app in the menu bar; quit from its menu to stop it. Hold **Option** while scrolling to temporarily bypass smoothing.

## Update

Quit SmoothWheel first. If you installed with Homebrew:

```sh
brew update
brew upgrade --cask antonmazur/tap/smoothwheel
```

For a manual installation, download the latest ZIP and replace the app in Applications. Open the updated app and enable smoothing again.

## If smoothing does not work

- Check **Enable smoothing** and the Accessibility permission. If permission is shown as enabled but input is not being processed after an update, quit the app, remove its old Accessibility entry, add the current copy from Applications, and reopen it.
- Check **App exclusions**. Exclusions apply to the foreground app, even when the pointer is over a background window.
- Record other active mouse or scrolling utilities in a [compatibility report](https://github.com/AntonMazur/SmoothWheel/issues/new?template=compatibility_report.yml). Continuous events, including trackpad input, pass through unchanged.

See [known limitations and compatibility reports](COMPATIBILITY.md) for current observations.

## Uninstall

Quit SmoothWheel from its menu-bar menu. If installed with Homebrew:

```sh
brew uninstall --cask smoothwheel
```

Otherwise, move **SmoothWheel.app** from Applications to the Trash. You can also remove its Accessibility entry in System Settings. Local preferences are retained.
