# Testing and measurement

Run on macOS with Xcode 16+ (Swift Testing). CI is pinned to macOS 26 for image baselines. No tests install an event tap, change Accessibility permission, modify the user's preferences, or post global input. Tests use local Quartz packets and isolated preferences. AppKit snapshot tests briefly order test windows off screen, then close them.

```sh
./scripts/test.sh
./scripts/measure-engine.sh
./build.sh
```

`test.sh` runs the functional suite, exports clean-run LLVM coverage, checks coverage floors, and validates generated tokens and semantic contrast. It enables UI snapshots automatically on macOS 26. Other OS versions skip the macOS 26 image baselines; CI provides the full check. Generated reports and images live in `artifacts/` and are ignored by Git. Functional and UI tests run in separate processes so synchronous image rendering cannot starve display-clock integration tests. Their profiles are collected and merged. Swift Testing writes separate functional/UI JUnit reports (the runner may add `-swift-testing` to the filename). CI uploads evidence even after failure.

## Behavioral regressions

`SmoothWheelAppCore` contains the same coordinator and UI used by the executable. Tests invoke the production `handle` and `tick` paths with injected target ownership, virtual time and a captured posting closure. They do not maintain a second scrolling implementation.

Annotated-recipient regressions reproduce an excluded chat switching to a windowed messenger and system overlay without an input pause, despite stale/missing AX results. They also check immediate exclusion on return, cancellation on pointer delivery to another process, and safe handling of unregistered process IDs.

The background-renderer regression compares actual emitted direction and distance for a sidebar and a registered document service. The default registry observes the workspace’s KVO-compliant running-app array, including background entries omitted by normal launch notifications. The physical Notes reference confirms that the real PaperKit process entered the cache; the registered-recipient unit test alone does not prove macOS lifecycle notification delivery.

The routing/frame golden checks native event identity and unchanged fields, excluded ChatGPT-like windows, system overlays, ordinary windowed messengers, unresolved targets, a late lookup within a native burst, and exact smoothed distance. Separate coordinator tests verify target-boundary cancellation, click/key/modifier interruption, continuous and synthetic passthrough, and suspension without a stale momentum jump. Resolver integration deliberately blocks a worker while the real display clock emits production frames, then invalidates the target and verifies native-burst continuity after completion. Resolver tests cover stale generations and transient failures. Existing motion/event tests cover reversal, both axes, distance conservation, frame rates, native AppKit scrolling, allocation failures, and the final landing.

Diagnostics tests exercise the asynchronous writer, coalesced flush requests, counters, per-owner routing, and latency percentiles. `Tests/SmoothWheelAppCoreTests/Fixtures/0.3.15-live-diagnostics.json` and `0.3.16-live-diagnostics.json` preserve physical-wheel runs as historical measurement references. The latter includes OS-assigned destination counts and the confirmed immediate Telegram transition. These published references retain aggregate metrics only; app-usage lists and process IDs are omitted. They are **not** input recordings or automated performance baselines.

## Snapshot review

Eight real AppKit content states cover paused and active scrolling, both appearances, empty and populated exclusions, and the playground. Each has a PNG and a JSON snapshot of visible control labels, values and bounds. The JSON also checks that the window supports the native close control; PNGs cover content, not the OS titlebar. Blank or uniform captures fail before comparison. Raster comparison permits up to 1% changed pixels above a 12/255 channel delta and at most 1/255 mean channel error. Layout/text JSON comparisons are exact.

A mismatch saves actual, expected, red difference images, and comparison statistics in `artifacts/tests/`. Inspect those and the JSON before changing a baseline. Baseline recording is explicit and forbidden when `CI` is set:

```sh
SMOOTHWHEEL_UI_SNAPSHOTS=1 SMOOTHWHEEL_RECORD_SNAPSHOTS=1 ./scripts/test.sh
```

Review the changed files under `Tests/SmoothWheelAppCoreTests/Snapshots/` before committing. Never automatically accept a CI image mismatch. OS font/raster changes can require a reviewed new baseline; they are not grounds to loosen the threshold silently. The full snapshot check currently targets macOS 26 on Apple Silicon.

## Coverage floors

`artifacts/coverage/llvm.json` contains per-line LLVM data; `summary.json` lists every production file and module, and `summary.md` is attached to CI. Raw profiles are deleted before each run, so old coverage cannot make a failing or filtered run appear complete. All test-bundle profiles and binaries are merged; SwiftPM versions can otherwise export only the final bundle.

Minimum production line coverage is 90% for ScrollCore, 85% for ScrollEvents, 75% for ScrollTiming, and 60% for ScrollEngine.swift. The UI, diagnostics, delegate and executable entry point remain visible in the report without an inflated whole-project coverage claim. An unlinked source is counted as uncovered using its source-line count because LLVM has no executable-line map for it. Coverage is a gap detector, not proof that every branch, input combination or OS integration works.

## Timing budgets

`measure-engine.sh` builds **release mode without coverage** and times the real coordinator on 5,000 measured inputs on each of the native, smoothed, and background-renderer paths, after 200 warmup inputs per path. It also times 1,250 frame-emission calls. The production recipient registry performs cached PID lookups. Background AX discovery is replaced by deterministic ownership and is outside the timed path. The virtual input cadence is 500 Hz with a tick every four inputs. Input objects are created before timing; output is captured locally. It emits p50/p95/maximum milliseconds to `artifacts/performance/callbacks.json`.

`check-performance.py` fails if any path has fewer than 1,000 samples or exceeds a 2 ms p95 budget. This is a broad regression guard against blocking work, not a claim that 2 ms is normal. Maximums are reported without a hard gate because scheduling pauses can distort a microbenchmark. The existing `benchmark-scroll.sh` and `benchmark-display-selection.sh` remain component benchmarks. Do not compare debug/coverage times to optimized measurements.

## Live validation boundary

These checks cannot prove the content rendering quality of Gmail, Telegram or a macOS popover. Real AX ownership discovery, Accessibility approval, event-tap installation, global posting, OS display scheduling, and another application's rendering still require a physical-wheel check. Automated resolver tests inject ownership because they must not depend on private windows, permissions, or the installed apps on a CI runner.

For an engine change: keep one mouse utility active, fix speed/smoothing/zoom, test native scrolling inside an excluded app, the system Applications overlay above it, and an overlapping windowed app. Collect opt-in diagnostics and note the exact app/OS/mouse plus any visual symptom. Report input callback latency, background probe duration and frame gaps separately. A long background probe is not a blocked input callback; emission pacing is not external-app FPS. Do not turn a successful replay or high coverage percentage into a claim that the physical issue is fixed.
