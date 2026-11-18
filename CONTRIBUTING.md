# Contributing to SmoothWheel

Thanks for helping make third-party mouse scrolling more comfortable on macOS.

## Develop

Use a Mac with Xcode 16 or newer (Swift Testing is required). Open `Package.swift` in Xcode, or use:

```sh
./scripts/test.sh
./build.sh
```

The app archive is written to `releases/SmoothWheel.zip`. This is an ad-hoc-signed local build, not a notarized release. Install it in a stable location before granting Accessibility access. Rebuilds can require removing and re-adding the permission.

## Useful contributions

- Try the [five-minute compatibility check](docs/COMPATIBILITY.md) and [share your results](https://github.com/AntonMazur/SmoothWheel/issues/new?template=compatibility_report.yml), including successful tests.
- Hardware reports: mouse brand/model, connection type, macOS version, other mouse software, and target app.
- App-specific problems: exact reproduction steps and whether holding Option fixes the issue.
- Scrolling-engine fixes: preserve trackpad events, input distance, immediate direction reversal, and fail-open behavior.
- Design improvements: preserve native macOS controls, keyboard operation, readable contrast, and system appearance.

See [testing and measurement](docs/TESTING.md) for replay snapshots, UI baselines, coverage floors, and callback budgets. On macOS 26, `./scripts/test.sh` runs UI snapshots by default; run `./scripts/measure-engine.sh` for optimized callback measurements.

Keep pull requests focused. Add meaningful tests when changing scrolling behavior. Run `./scripts/test.sh` and `./build.sh` before submitting. Avoid adding a vendor dependency or collecting input telemetry.

Open issues and pull requests at https://github.com/AntonMazur/SmoothWheel. The website is maintained in a separate repository.
