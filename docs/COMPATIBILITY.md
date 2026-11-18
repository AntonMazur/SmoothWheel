# Hardware and app compatibility

Help us find out how SmoothWheel feels on real mice and in everyday Mac apps. Successful runs and problems are both useful: [submit a compatibility report](https://github.com/AntonMazur/SmoothWheel/issues/new?template=compatibility_report.yml).

## What we have verified

These are individual observations, not certification of a whole brand. Automated regression tests are documented separately in [PERFORMANCE.md](PERFORMANCE.md).

| Mouse / environment | SmoothWheel version | Observation | Evidence and limits |
| --- | --- | --- | --- |
| Physical Razer mouse; exact model, connection, and macOS version not recorded | 0.3.3 | Wheel events reached the smoothing engine; output followed the current pointer position during scrolling | [Hands-on validation](SCROLLING-FIX.md). Does not establish current-version compatibility across Razer models or apps. |
| Gmail in Chrome; hardware and macOS version not recorded | 0.3.11 | Residual landing movement remains reported; the 0.3.10 Chrome-specific trial was reverted | [Investigation and reversion](PERFORMANCE.md). Needs a fresh report with exact hardware, app versions, and settings. |

There are no complete community reports for the current release in this table yet. We will add reports with a source link, app version, and enough detail to reproduce the result. Older reports remain version-specific.

## Where testing helps most

- Standard discrete mouse wheels from Logitech, Razer, Microsoft, and other brands; wired, Bluetooth, and USB receivers.
- Everyday scrolling in Safari, Chrome, Firefox, Finder, and a text editor. Gmail in Chrome is especially useful for checking the known landing behavior.
- macOS 13, the oldest targeted version, and newer macOS releases. The downloadable build is for Apple Silicon; Intel builds need separate validation.
- Mixed mouse and trackpad use, app exclusions, and a brief check after sleep/wake.

## Five-minute check

1. Record the SmoothWheel version, mouse model and connection, macOS version, and app/browser version. Note other running mouse utilities; their behavior may affect the result.
2. Open SmoothWheel, confirm Accessibility access, and turn on **Enable smoothing**. It starts disabled on each launch. Start with **Balanced** and record the speed, smoothing, and reverse-direction settings.
3. In the built-in **Playground** and at least one everyday app, try short wheel steps, a longer scroll, stopping, and reversing direction. Report jumps, shaking, continued motion, or unexpected pointer movement. Check horizontal scrolling if your mouse supports it.
4. Hold **Option** while scrolling to compare bypass behavior. Add one test app to **App exclusions**, bring it to the foreground, and check that its original scrolling returns. If you use a trackpad, check that its continuous scrolling feels unchanged.
5. [Submit your results](https://github.com/AntonMazur/SmoothWheel/issues/new?template=compatibility_report.yml), including successful checks and anything you could not test. Optional: repeat a short check after sleep/wake.

Exclusions follow the foreground app, even when the pointer is over a background window. The current download is ad-hoc signed and not notarized; see the [setup guide](../README.md#get-started) before testing.

A written report is enough. If a recording helps explain a problem, use the Playground or another non-sensitive test page. No private documents, mailbox content, device serial numbers, or diagnostic dumps are needed.
