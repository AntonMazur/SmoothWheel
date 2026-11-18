# Changelog

## 0.3.17 — 2026-11-19

Public update from 0.3.11, including the 0.3.12–0.3.16 development fixes below.

### Improved scrolling

- **Immediate smoothing after switching apps.** Use macOS’s assigned event recipient and cached process identities, so a scroll in excluded ChatGPT no longer keeps the next Telegram or system-overlay scroll native while a hit-test catches up.
- **Consistent scrolling in Notes attachments.** Track background renderers through the workspace’s running-app updates. Embedded documents now receive the same smoothing and reverse-direction settings as the notes list; the physical trial confirmed both.
- **Keep blocking work away from input and frames.** Accessibility hit-testing runs on a coalesced worker only as a fallback. Known recipients use a cached identity lookup, without per-wheel process queries. Old lookup completions cannot override a known event recipient.
- **Avoid mixed wheel bursts.** Unknown recipients pass through natively for their current burst; switching to a different known process starts a new routing transaction. Input distance, the existing motion curve, display pacing, and trackpad passthrough remain unchanged.
- **Regression protection.** 45 functional tests, eight light/dark UI snapshot states, line-coverage floors, and release-mode callback budgets now run in CI. Replays cover exclusions, system overlays, overlapping apps, delayed lookups, background renderers, direction and distance.

### Public measurements

One physical Razer-wheel session on Apple Silicon, macOS 26.6.2, using the display-linked clock:

| Measurement | Result |
|---|---:|
| Routed wheel events / generated output frames | 692 / 8,372 |
| Input-callback time, p95 / maximum | 0.228 / 1.185 ms |
| Emission-frame interval, p95 / maximum | 8.766 / 25.215 ms |
| Unknown event destinations in this sample | 0 |
| Motion-core / events-and-routing line coverage | 97.18% / 87.79% |
| Frame-clock / coordinator line coverage | 76.36% / 74.58% |

These timings measure SmoothWheel’s callbacks and emission cadence, **not another app’s rendering FPS or end-to-end input latency**. This is one development session, not a controlled before/after or competitor benchmark. Optimized local callback measurements also passed the 2 ms p95 regression budget; those exclude global posting and rendering. [Aggregate JSON and complete measurement scope](docs/metrics/v0.3.17.json), [methodology and limitations](docs/TESTING.md).

The measurements contain no recordings, note contents, app-usage list, process IDs or local filesystem paths. The app still collects no analytics; diagnostics are opt-in and local.

### Distribution

Apple Silicon, macOS 13+ target; ad-hoc signed and not notarized. The oldest supported macOS and Intel remain unvalidated. Updating may require removing the old Accessibility entry and adding the current app from Applications, then enabling smoothing again. Residual landing behavior in Gmail remains a known compatibility report; this release does not claim every visual hitch is resolved.

## 0.3.16 — 2026-11-19

- Route using the OS-assigned receiving process at the annotated-session event tap, with process identities cached outside the input callback. Known destinations no longer wait for Accessibility hit-testing when changing applications.
- Scope burst continuity to the receiving process so an excluded ChatGPT burst cannot keep a new Telegram or system-overlay transaction native. Late AX results cannot cancel a known recipient’s smoothed motion.
- Cancel pending motion on pointer delivery to another receiving process. Retain asynchronous AX resolution only for events without recipient metadata; unregistered annotated processes pass through natively when exclusions are set.
- Add production-coordinator regressions for immediate excluded-app/messenger/overlay transitions with stale or missing AX data, process-cache lifecycle checks, and diagnostic destination-source counts. Live validation confirmed immediate Telegram smoothing with ChatGPT excluded; the captured run used only known OS annotations. This does not establish that every unrelated frame hitch is resolved.

## 0.3.15 — 2026-11-18

- Separate asynchronous target resolution, wheel-burst routing, motion integration, and display pacing. No Accessibility IPC or window-list queries run inside the input tap or frame callback.
- Coalesce pointer-driven lookups on a serial worker, reject stale results, and retain valid snapshots across transient failures. No app-specific behavior.
- Keep a native burst native until its input pause, including after late resolution or replacement-allocation failure. Cancel pending motion across target boundaries.
- Apply the same receiving-window rules to Telegram, inactive or overlapping windows, excluded apps, and system popovers.
- Add resolver lifecycle, stale-result, transient-failure, routing, and stalled-target/display-clock regressions. Extend opt-in diagnostics with input-callback latency and background-probe timing. Physical-wheel validation is separate.

- Make the production coordinator and settings UI importable by tests. Add golden routing/frame replays, eight light/dark AppKit content snapshots, diagnostic-writer integration coverage, clean-run line coverage floors, optimized callback budgets, and CI artifacts.

## 0.3.14 — 2026-11-18

- Resolve the Accessibility element under the wheel pointer whenever exclusions are set, so excluded background windows remain native even while another app has focus.
- Stop using arbitrary window-server ownership to override exclusions. Unresolved Accessibility targets pass through natively; system popovers use their own process identity.
- Bound hit-test messaging time and keep hit-testing out of the display-frame loop. Filter overlay bounds by the resolved process.
- Add a background-window regression and optional local per-process routing counts for physical-wheel diagnosis. Live behavior still requires confirmation.

## 0.3.13 — 2026-11-18

- Correct the Applications-popover case shown in the recording: keep the tap active and resolve window ownership on wheel input when the foreground app is excluded.
- Preserve native scrolling inside excluded windows while allowing smoothing in system popovers owned by another process. Unknown owners fall back to the foreground exclusion.
- Cancel a popover's pending scroll when the pointer leaves its bounds or a key/click dismisses it. Window metadata is never queried in the display-frame loop.
- Add regression tests for popover ownership, visibility, hit-test order, and unresolved-owner fallback. Physical-wheel verification remains required.

## 0.3.12 — 2026-11-18

- Disable the event tap entirely while an excluded app is foreground, allowing native wheel events to reach that app and system popovers without SmoothWheel interception.
- Resume interception when another app activates or an exclusion is removed; cancel pending animation on exclusion changes.
- Keep the health check from treating an intentionally bypassed tap as a failure and pausing smoothing globally.
- Hardware confirmation of the reported ChatGPT/Applications-folder issue is still required.

## 0.3.11 — 2026-11-14

- Revert the Chrome-specific gesture-phase trial after the user reported worse Gmail scrolling.
- Restore 0.3.9 event handling for every app, including Chrome. The bounded landing and saved settings remain in place.

## 0.3.10 — 2026-11-14

- Trial explicit began/changed/ended scroll phases for Google Chrome while retaining legacy precise-wheel events in other apps.
- End and cancellation packets carry zero movement; allocation failure retries the final end packet.
- Avoid sending an old target’s cancellation into a newly focused app.
- Add phase conversion, cancellation, and final-packet retry tests; all 30 tests pass.

## 0.3.9 — 2026-11-14

- Finish the last three pixels in a bounded 60 ms landing, avoiding increasingly separated single-pixel packets near rest.
- Preserve final rounded distance and let new wheel input interrupt the landing.
- Ignore zero-axis additions so unrelated-axis input cannot restart a landing.
- Add landing monotonicity, spacing, interrupted-input, and zero-axis regressions.

## 0.3.8 — 2026-11-14

- Centralize native preset labels, matching, and defaults in a shared typed model.
- Coalesce optional diagnostic snapshots and move sorting, JSON encoding, and disk writes to a serial utility queue.
- Invalidate event-tap resources before engine teardown and stop the health timer at app termination.
- Make frame-clock main-thread ownership explicit. The validated motion curve is unchanged.

## 0.3.7 — 2026-11-14

- Remove the requested trackpad and exclusions footnotes and reduce settings-window height by 30 points.
- Cache active-display bounds to avoid per-notch screen queries and clock-handler allocations on the same screen.
- Invalidate the cached selection on display reconfiguration and preserve retargeting across screens.

## 0.3.6 — 2026-11-14

- Pace scrolling with the target screen’s display link on macOS 14+, with a screen-rate timer fallback on macOS 13.
- Preserve velocity between wheel notches using a critically damped motion curve instead of repeated abrupt velocity impulses.
- Limit integration after a delayed frame to avoid a large catch-up jump while retaining pending distance.
- Extend local diagnostics with clock mode, frame intervals, and largest output frame.
- Add actual display-clock lifecycle tests, notch-transition tests, and delayed-frame regressions; all 23 tests pass.

## 0.3.5 — 2026-11-14

- Finish animation tails at a subpixel threshold while preserving rounded wheel distance, and skip integration on idle axes.
- Coalesce the background health timer and avoid refreshing hidden settings views.
- Restore a standard AppKit titlebar with native window controls; closing settings keeps the menu-bar utility running.

## 0.3.4 — 2026-11-14

- Triple the scroll-distance baseline so 1× is substantially faster, with the same proportional increase across presets and both wheel axes.
- Retain smoothing timing, preset ratios, pointer handling, and trackpad passthrough.
- Verify the new distance calibration across the speed range and in a native scroll view.

## 0.3.3 — 2026-11-14

- Stop replaying the last wheel tick’s cursor position in smoothing frames, which could pull the pointer backwards while it was moving.
- Add regression coverage for pointer movement during a pending smoothing tail, plus opt-in local event-delivery diagnostics for development.
- Give the corrected icon a new resource name and load the application icon explicitly to refresh cached references.

## 0.3.2 — 2026-11-14

- Replace the handwritten ICNS packager with Apple iconutil so small app lists receive standard and Retina icon representations.
- Verify the compiled icon round-trips to all ten required PNG representations before signing the app.

## 0.3.1 — 2026-11-14

- Fixed dropped wheel movement caused by small pointer movements, transient event flags, and gaps between wheel notches.
- Preserve native pixel distances and fractional wheel input; create fresh precise pixel events for every frame.
- Keep generated wheel events free of artificial trackpad phases, and preserve pending distance if frame allocation fails.
- Remove expensive permission, foreground-app, and pointer polling from the frame loop.
- Add regression coverage for Quartz events, AppKit conversion, repeated input, and actual movement of a native scroll view. All 16 tests pass.

## 0.3.0 — 2026-11-14

- Implemented the selected Soft Form design in the native app and website.
- Added a shared JSON token source, generated Swift/CSS tokens, reusable native controls, and an interactive design-kit page.
- Added the original wheel hero and coral brand assets, locally bundled Manrope, and licensed Phosphor web icons.
- Removed the duplicate Paused badge and added the preferred Accessibility setup row.
- Kept source and download button typography consistent.
- Added contrast and token-drift checks, and changed app pickers and alerts to nonblocking sheets.

## 0.2.0 — 2026-11-14

- Redesigned native settings with a sidebar, permission card, grouped controls, and clear status.
- Added Precise, Balanced, and Relaxed presets.
- Added an app picker and editable exclusion list.
- Added a built-in scroll playground.
- Separated the project into its own repository folder.
- Prepared an MIT license, contributor guide, CI workflow, issue template, and product website.

## 0.1.0 — 2026-11-14

- Initial native menu-bar utility, mouse-wheel smoothing, direction control, per-app exclusions, and Option bypass.
- Core tests for distance preservation, reversal, reset, and bounded input.
