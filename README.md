# SmoothWheel

**A familiar mouse. A smoother Mac.**

A native macOS menu-bar utility for comfortable scrolling with standard third-party mouse wheels. Swift and AppKit. MIT licensed.

## Status

Version **0.3.11** is an Apple Silicon prototype, ad-hoc signed and not notarized. Physical Razer testing and native event/frame-clock regressions have been performed; broad application compatibility and the oldest supported macOS still need validation. Slight landing movement remains reported in Gmail. The reverted Chrome-specific trial is documented in the changelog.

Source: [AntonMazur/SmoothWheel](https://github.com/AntonMazur/SmoothWheel).

## Features

- Smooth discrete vertical and horizontal wheel input across brands, with speed and smoothing controls.
- Precise, Balanced, and Relaxed presets. The 1× baseline travels three times the native wheel distance.
- Independent wheel direction; continuous trackpad events pass through.
- Per-app exclusions and a built-in scroll playground.
- Option bypass and Control/Command scrolling-shortcut passthrough.
- Local preferences, with no account, analytics, or network requests from the app.

Exclusions use the foreground app, including when hovering over background windows. Continuous events from other utilities pass through unchanged.

## Build and test

Requires macOS with Xcode 16+ and Swift Testing. The package targets macOS 13; the host architecture is built. macOS 14+ uses a display-linked clock, with a timer fallback on macOS 13.

```sh
./scripts/test.sh
./build.sh
./scripts/package-source.sh
```

The app ZIP is `releases/SmoothWheel.zip`. Extract it, move SmoothWheel to Applications, and grant access in **System Settings → Privacy & Security → Accessibility**. Enable smoothing and start with Balanced. Smoothing starts disabled each launch. Rebuilding changes the ad-hoc signature and may require refreshing its existing Accessibility approval. Close settings to keep the menu-bar utility running; quit from its menu.

## Structure

- `Sources/ScrollCore`: motion mathematics and shared presets.
- `Sources/ScrollEvents`: testable Quartz event conversion.
- `Sources/ScrollTiming`: target-display frame clock.
- `Sources/SmoothWheel`: native app, controls, and engine lifecycle.
- `Tests`: motion, event-packet, native scrolling, and clock regressions.
- `design/tokens/soft-form.json`: native design-token source.
- `scripts`: build support, validation, and reproducible benchmarks.
- `docs`: release steps and performance investigations.

The website is a separate project. No website source, design boards, or website Git history is included here.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) and [release preparation](docs/RELEASE.md). Use focused pull requests and meaningful behavior tests. There are no third-party runtime dependencies.

## License

[MIT](LICENSE). Independent project; no affiliation with Apple, Razer, or other mouse manufacturers.
