# Scrolling performance — 0.3.5

The engine remains native Swift/AppKit. Rust can target macOS, but the measured smoothing calculation is already very small; changing language has no demonstrated benefit for this workload. The current optimization targets unnecessary animation work instead.

## Repeatable benchmark

Run `./scripts/benchmark-scroll.sh` on macOS. It builds optimized code, creates local Quartz event objects, and simulates independent 90-pixel bursts at 120 Hz for the three smoothing settings. It never posts global events. It also times one million smoothing steps and retains a checksum. Execution times vary with CPU load and compiler; simulated tick counts and output distance are deterministic. These measurements do not measure display presentation, global event-tap latency, or physical mouse feel.

Before and after results on this Apple Silicon Mac:

- Precise smoothing: 68 → 39 timer ticks, with no-output ticks reduced from 41 to 12.
- Balanced smoothing: 127 → 73 timer ticks, with no-output ticks reduced from 87 to 33.
- Relaxed smoothing: 196 → 112 timer ticks, with no-output ticks reduced from 143 to 59.
- All six bursts produced exactly 90 pixels. Balanced used about 43% fewer timer ticks for this isolated burst.
- The mathematical core measured about 17 ns/step before and 14 ns/step after in one run. These small timings are illustrative, not a statistically established CPU-speed claim.

The smoother now emits its rounded final residual when less than half a pixel remains, rather than keeping its timer alive down to 0.01 pixel. A completely idle axis returns before computing exponential decay. The frame timer still runs only while movement is pending and uses the same elapsed-time integration, 120 Hz rate, and smoothing constants. The 0.3.4 speed increase remains in place.

The health timer now has a 0.4-second tolerance on its 2-second interval. Hidden settings views skip periodic refresh, and are refreshed when opened. This gives macOS flexibility to coalesce idle work without loosening the active frame clock.

Validation: all 20 tests passed, including rounded distance conservation, fractional tails, reversal, multiple frame rates, both axes, speed calibration, allocation-failure retries, current pointer locations, and actual movement in a native AppKit scroll view. The prior physical Razer validation is documented in `SCROLLING-FIX.md`; the new tail optimization is verified by the benchmark and regression suite, not a new physical-hardware run.

References: [Apple Timer documentation](https://developer.apple.com/documentation/foundation/timer), [Rust macOS target support](https://doc.rust-lang.org/rustc/platform-support/apple-darwin.html).

The installed build was checked with Accessibility ready and smoothing enabled using the existing saved speed, smoothing, and direction settings. The native close control was invoked; the settings window reopened with smoothing still enabled in the same app session. The standard titlebar reserves its own space above the custom content. During computer-use sharing, macOS may place its sharing indicator over the titlebar controls.

## 0.3.6 — motion pacing

The previous callback-count optimization did not establish that motion was visually smooth in other apps. The next correction addresses pacing and velocity continuity. On macOS 14 and later, `NSScreen.displayLink` drives output on the display under the physical wheel event. It is independent of the utility’s own settings window, continues when settings are closed, and stops when movement ends. The clock retargets on a subsequent wheel event on another screen. macOS 13 retains a timer fallback using the screen’s advertised maximum frame rate. All clock and event-stream state remains on the main run loop in common modes; no background frame backlog is created.

A critically damped response now preserves velocity when additional same-direction notches change the destination. A small initial velocity keeps initial input and reversals responsive. Each integration step is capped at 1/30 second: a late callback extends the tail instead of dumping all overdue movement in one frame. The existing 0.5-second stale-session cancellation remains. Wheel distance, speed calibration, pointer position handling, and continuous-event passthrough remain covered by regression tests.

All 23 tests pass. A native screen display link was exercised through start, ticks, stop, and restart. Additional tests check bounded output changes across a new notch, delayed-frame behavior, fractional distance, native AppKit scrolling, and reversal. The earlier 0.3.5 callback benchmark is historical; its 43% reduction is not a measurement of perceived smoothness or the new motion curve.

Live diagnostics now include clock mode, p95 and maximum frame interval, and largest vertical output packet. These record the utility’s event emission, not the external application’s actual rendering or reload state. A visual report from the affected application is still needed to confirm the reported jump is resolved.

Reference: [Apple NSScreen display link](https://developer.apple.com/documentation/appkit/nsscreen/displaylink(target:selector:)).

### External-app validation

The user reported “Smoother now” after the 0.3.6 external-app test. The instrumented run accepted 398 physical wheel events, posted 3,621 frames, and recorded 3,916 clock intervals. It used the native display-link mode; p95 interval was 8.51 ms and maximum was 17.03 ms. The maximum pre-post pointer-position mismatch was 0 pixels. The user's saved speed (~1.97×), smoothing (~65%), and reversed direction were retained. These measurements describe emission pacing, not the external app's presentation timing. The affected app was not named. Temporary diagnostics were disabled after validation.

## 0.3.7 — cached display selection

Repeated notches on the active display now take a cached rectangle check, avoiding a CoreGraphics display query and a new frame-handler closure. Crossing a display boundary reselects the display. A screen-configuration notification cancels the existing clock, so changed geometry is selected afresh on the next wheel event. Stop also clears the cached bounds. The motion curve, speed gain, pointer behavior, and frame cadence are unchanged.

Run `./scripts/benchmark-display-selection.sh` for an optimized-build comparison without posting input. In five samples of 20,000 checks, median system-query cost was 39,685 ns/check versus 4.62 ns/check for cached bounds on this machine. This is a component microbenchmark, not an end-to-end speedup or a display-latency claim. The cached path removes the system call rather than translating it into another language. Rust was considered; no Rust toolchain was installed and no Rust-versus-Swift benchmark was performed. The existing tiny math cost and avoidable OS lookup did not justify adding a language boundary or rewriting the validated motion engine.

All 23 tests pass, including keeping the existing display clock on same-screen input and clearing tracking state on stop. The settings copy and compact layouts were also checked in the installed app.

## 0.3.8 — code polish and comparison recording

The supplied 29.38-second, 120-fps recording shows SmoothScroll first, then SmoothWheel after its settings window opens around 14 seconds; the user confirmed that order. SmoothWheel is enabled around 15.5 seconds at about 2× and 65% smoothing. Menu changes and opening/closing settings are not comparable scroll segments. The host editor is Xcode with a debugging session visible.

Short scroll passages from roughly 3–9 seconds and 17–23 seconds both contain large fast movements. Exploratory row-profile tracking at 60 samples/second found comparable upper-end displacements; it did not establish a consistent smoothness winner. The inputs, travel directions, acceleration histories, and utility settings were not matched. The recording contains no CPU, energy, raw wheel-input, or presentation-latency measurements. It therefore cannot support a performance ranking, a reload diagnosis, or a claim that matching the competitor requires different motion math. A controlled next comparison should isolate one utility at a time, match total travel, and record the same wheel sequence and host workload.

Cleanup keeps the accepted 0.3.6 motion curve and 0.3.7 screen cache intact. Shared preset definitions replace repeated tuples in the native UI and defaults. Engine teardown invalidates its borrowed event-tap callback before releasing the engine. Frame-clock entry points enforce main-thread ownership. Optional diagnostic requests are coalesced over 100 ms; immutable Sendable snapshots are sorted, encoded, and written on a serial utility queue, instead of performing filesystem work inside the input callback. Normal runs still create no diagnostic logger or writes.

Validation: all 24 tests passed, including native frame-clock lifecycle, event packet conversion, actual native scrolling, distance conservation, pointer positions, and preset matching. A separate asynchronous-writer check issued 500 updates/flush requests and verified the resulting snapshot retained all 500 updates. This establishes correctness of the cleanup, not an increase in normal-use FPS. No third-party implementation code was read or copied.

## 0.3.9 — final-pixel landing

The new recording reports a small shake immediately before rest. Only SmoothWheel was running when checked. An isolated 90-pixel burst at 65% smoothing reproduced a sequence of one-pixel packets separated by growing zero-output gaps near the end; it did not reproduce reverse-direction packets. The user could not tell whether the visual symptom was backward movement or tiny separated steps, so the symptom's root cause is not conclusively established from the recording alone.

The engine now finishes its last three pixels over a bounded 60 ms segment. This avoids the long, sparse integer-pixel tail while preserving the final rounded distance. New nonzero wheel input interrupts the landing and resumes the existing damped response. Zero-axis input is ignored so motion on another axis cannot restart the segment. A local Quartz probe confirmed that setting fractional fixed-line values alone did not yield fractional precise deltas in NSEvent, so unsupported fractional packet mutation was not adopted.

Validation includes no reverse packets for either direction, bounded silence between final pixels in the representative 120 Hz bursts, exact rounded distance, new input during landing, and zero-axis input during landing. Visual confirmation in the affected app remains separate from these deterministic event-stream tests.

## 0.3.10 — Chrome compatibility trial

The user reported a steadier landing in Codex with 0.3.9, but residual shaking in Gmail in Chrome at 100% zoom. Chromium's wheel phase handler synthesizes transaction phases for phase-less input. This suggests a compatibility hypothesis; it does not prove Gmail's shake is caused by missing phases. Reference: https://raw.githubusercontent.com/chromium/chromium/main/content/browser/renderer_host/input/mouse_wheel_phase_handler.cc .

Only Google Chrome now opts into explicit begin/update/end phases. Other apps, including Codex and native controls, retain legacy precise-wheel behavior. The final packet is zero-distance; cancel also emits zero distance when appropriate. A foreground-app change resets the old stream without posting its cancellation into the newly focused app. Speed, the 60 ms final-pixel landing, pointer handling, and trackpad passthrough are unchanged.

All 30 tests pass, including native phase conversion, movement conservation, zero-distance termination/cancellation, and retrying an end-packet allocation failure. These tests validate the packet lifecycle; Gmail's perceived landing requires a separate user check. No mailbox content is needed or stored in the project for this investigation.

## 0.3.11 — Chrome trial reverted

The user reported that 0.3.10's Google-specific phase handling made Gmail scrolling worse and explicitly requested its removal. The event stream, engine, and event tests were restored to their exact 0.3.9 versions. All apps again use legacy precise-wheel packets without fabricated gesture phases. The bounded final-pixel landing, display pacing/cache, and earlier code cleanup remain. This reversion does not claim the residual Gmail shake is resolved.


## 0.3.15 — target resolution outside the event path

The 0.3.14 physical run recorded 40 unresolved hit-tests, 61 native ChatGPT events, and 237 smoothed Spotlight events. Its maximum frame gap was approximately 102.7 ms (p95 14.4 ms). These are emission measurements, not rendering FPS. Per-wheel synchronous Accessibility calls and window enumeration shared the animation run loop; transient failures could alternate raw and synthetic packets inside one wheel burst. The recording and reports also cover ordinary overlapping windows, including Telegram.

The coordinator now performs only local routing and motion work in its input/frame callbacks. `ScrollTargetResolver` coalesces pointer, click, keyboard, app-activation and wheel requests onto one serial worker. It publishes immutable owner/bounds snapshots on the main loop. Generation checks reject obsolete work; failed probes retain a snapshot only if it is still valid for the pointer. There is at most one lookup in flight and one latest pending point; no idle polling loop or app-name exceptions.

`ScrollRoutingState` gives every wheel burst a consistent native/smoothed path. An unresolved initial burst remains native through its input pause rather than switching after a late result. Entering an excluded target cancels pending motion. The existing mathematical response, speed settings, native packet construction and display clock remain unchanged.

Tests deliberately stall target lookup while the real display clock ticks, exercise stale completions and transient failures, and cover inactive excluded windows, native-burst continuity and allocation failure. Optional local diagnostics now distinguish input-callback p95/maximum from background-probe timing and display-frame gaps. A new physical run is needed before claiming a measured latency or perceived-smoothness improvement.


### 0.3.15 physical run and automated guardrails

After the user refreshed permission and exercised ChatGPT, the Applications overlay and windowed Telegram, the captured report routed 30 events natively to Codex, 59 smoothed to Spotlight and 41 smoothed to Telegram. Input callback p95 was 0.191 ms (maximum 0.536 ms), frame-interval p95 8.607 ms (maximum 16.630 ms), with no pre-post pointer mismatch. Target probes reached 267.823 ms and failed 56 times; that work ran outside the input/frame callbacks. The earlier 102.7 ms maximum frame gap and this run used different input, so they are not a controlled performance comparison. The user has not yet confirmed that every visual symptom is gone.

The report is retained under `Tests/SmoothWheelAppCoreTests/Fixtures/0.3.15-live-diagnostics.json`. Automated production-coordinator replay snapshots, eight AppKit UI states, asynchronous diagnostic-writer coverage, per-module coverage floors and an optimized callback benchmark now supplement live measurements. See [testing and measurement](TESTING.md). Callback timing and packet snapshots still do not measure another application's rendering.


## 0.3.16 — immediate routing from the annotated event recipient

The user confirmed that Telegram eventually normalizes after switching from excluded ChatGPT. The prior model could pass the first wheel input natively while waiting on a target probe, then latch that whole burst native for consistency. More helper coverage alone did not eliminate this startup delay.

The input tap now runs at `cgAnnotatedSessionEventTap`, where macOS has assigned the receiving application. A lifecycle-maintained PID-to-bundle-ID cache supplies identity without per-event AppKit queries. Known recipients bypass the AX routing dependency. A different annotated PID begins a separate routing transaction even inside the previous 180 ms input burst; late AX completions cannot override that recipient. AX remains a fallback for events with no destination metadata, and unknown positive PIDs fail open when exclusions are configured. No Telegram/ChatGPT-specific policy is introduced.

Production-coordinator tests first reproduced the immediate-switch failure, then passed with missing/stale AX ownership and unchanged event identity in the excluded app. Diagnostics now separate annotated, unknown, and fallback destinations so a live trial can establish whether WindowServer supplied metadata, instead of inferring success from owner counts alone.

Reference: [Apple annotated event-tap stage](https://developer.apple.com/documentation/coregraphics/cgeventtaplocation/cgannotatedsessioneventtap), [event target process field](https://developer.apple.com/documentation/coregraphics/cgeventfield/eventtargetunixprocessid).


### 0.3.16 live validation

After installing 0.3.16, refreshing its existing Accessibility permission, enabling smoothing and visibly adding `com.openai.codex` to exclusions, the user repeated the immediate ChatGPT-to-Telegram switch and reported **“Smooth immediately.”** The captured run recorded 294 annotated destinations, 90 unknown destinations and 0 fallback destinations. Routing was 85 native Codex events, 47 smoothed Telegram events and 125 smoothed Spotlight events. The production recipient path therefore operated on actual wheel events without waiting for AX ownership.

Input callback p95 was 0.193 ms (maximum 3.991 ms). Frame-interval p95 was 8.647 ms, with a maximum of 108.302 ms; the run does **not** establish that every frame hitch or landing symptom is gone. Pointer mismatch was 0 pixels. The report is retained as `Tests/SmoothWheelAppCoreTests/Fixtures/0.3.16-live-diagnostics.json`, separate from deterministic replay baselines. Local validation passed 44 functional tests, eight UI states, production coverage floors, release callback budgets and the native app build.


## 0.3.17 — embedded document recipients

The user reported unsmoothed scrolling in the opposite direction only inside embedded Notes documents; the sidebar and ordinary text notes were correct. The 0.3.16 session recorded 141 unknown destinations passed through natively, which bypassed both smoothing and the user’s reverse setting. The cache watched normal launch/termination notifications, which Apple explicitly excludes for background apps and agents.

The registry now observes `NSWorkspace.runningApplications` with KVO. It publishes the same PID-to-bundle-ID dictionary used by the validated 0.3.16 callback path, retaining background services alongside UI apps. There are no per-wheel process queries, app-name exceptions, or extra OS lookups in the frame loop.

A window-number mapping prototype was evaluated during diagnosis. The actual wheel events carried no window-number annotations, and the successful trial recorded zero window-resolved events. That unused route and its window enumeration were removed from the final build. The physical cause was the missing background-service identity, not a different motion curve or a window geometry rule.

The user reported **“Both correct”** for the embedded document and notes list. The live report explicitly includes smoothed `com.apple.PaperKit.extension.ui` events, alongside Notes, with zero unknown destinations. `Tests/SmoothWheelAppCoreTests/Fixtures/0.3.17-notes-validation.json` preserves the trial counters (including the unused prototype’s zero window-resolution count). The final cleanup preserves the KVO registry and PID routing that handled that trial.

The production-coordinator regression emits 90 reversed pixels for both a sidebar and registered background renderer. The optimized benchmark separately checks background-recipient ingestion. Unit tests do not launch a real Notes/PaperKit service or prove its macOS lifecycle delivery; the physical trial establishes that boundary. The recording contains private document content and is not included in test fixtures or source archives.

Reference: [Apple workspace launch-notification exclusions](https://developer.apple.com/documentation/AppKit/NSWorkspace/didLaunchApplicationNotification), [running-app KVO](https://developer.apple.com/documentation/appkit/nsworkspace/runningapplications).
