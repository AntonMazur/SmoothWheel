# Scrolling correction — 0.3.1

The previous engine discarded pending movement after a four-pixel pointer change, an exact raw event-flag mismatch, or a gap between wheel notches. It also replaced native pixel distance with a fixed multiplier of integer line ticks. These paths can interrupt scrolling and lose movement.

The engine now retains pending distance during ordinary pointer movement and repeated wheel input, compares only keyboard modifiers, and uses native point deltas with fractional-line fallback. Foreground-app changes, mouse clicks, shortcuts, sleep, and long run-loop suspensions still cancel stale movement. Permission and foreground-app checks are outside the frame loop.

Each output frame uses the Quartz pixel-event initializer with a fresh timestamp. Quartz maintains the linked delta fields; manually writing rounded line deltas can erase small pixel frames. Output uses precise legacy mouse-wheel events with no synthetic trackpad gesture phases. Replacement allocation failure retains pending distance for retry. Trackpad and shortcut events pass through.

Validation: 16 automated tests passed, including distance conservation at 60/120/144 Hz, repeated input, transient flags, pointer movement, reversal, both axes, fractional wheels, allocation failure, Quartz-to-AppKit delta conversion, and an actual native NSScrollView moving from the generated sequence. Tests create local event objects and an unshown native window; they do not post global input. Release packaging also verifies the signed app and static website references.

Physical Razer behavior, global event-tap delivery, and compatibility across applications still require hands-on validation. Start with Balanced at 1× speed. Smoothing starts disabled on launch; re-enable it after opening this build. A rebuilt ad-hoc signature may require removing and re-adding the app in Accessibility settings.

## Pointer and icon follow-up — 0.3.3

Each output frame now retains the current cursor position provided by the native event constructor. The previous implementation overwrote it with the location of the last physical wheel tick, so continued pointer movement during the smoothing tail could be pulled backwards. The new regression test changes the current pointer position between generated frames and verifies that the old tick location is never replayed. All 17 tests pass.

The corrected icon uses a new resource filename. On this Mac, the installed app initially still resolved to the old corrupted small image. Replacing the app and refreshing its registration corrected NSWorkspace's installed-path lookup; restarting System Settings also corrected the icon shown in its Accessibility list. Merely verifying an icon in the staging directory was insufficient.

For local development, set `SMOOTHWHEEL_DIAGNOSTICS` to a writable JSON path when launching the executable. This opt-in report counts accepted discrete input, continuous bypass, generated frames, aggregate pixel distance, changes of output location, and the maximum distance between a generated frame's location and the current pointer before posting. It does not store absolute coordinates or key input. Normal launches create no diagnostic file.

Live validation completed with the user turning the physical Razer wheel while moving the pointer. The installed 0.3.3 build, on Balanced at 1×, accepted 150 discrete events and posted 1,083 frames spanning 5,398 absolute vertical pixels. Output positions changed during the test, and the maximum measured difference from the current pointer position immediately before posting was 0 pixels. This verifies the actual event-tap and posting path for this hardware run; it does not establish compatibility with every application or mouse. Native automation scroll actions moved the playground but did not enter this global event tap, so those actions were not counted as hardware validation. The corrected icon was observed in System Settings after restarting it. The temporary diagnostics were then disabled and normal Balanced operation restored.
