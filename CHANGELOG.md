# Changelog

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
