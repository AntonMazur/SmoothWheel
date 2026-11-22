# Architecture and project structure

Use this map when planning a feature. `Package.swift` is the source of truth for target dependencies. Place behavior in its existing responsible module and keep dependency direction consistent; propose a structural change in the feature review when necessary.

## Production modules

| Path / target | Responsibility | Package dependencies |
| --- | --- | --- |
| `Sources/ScrollCore` | Motion mathematics and shared preset definitions | None |
| `Sources/ScrollEvents` | Quartz packet conversion, burst routing, recipient registry, asynchronous target resolution | `ScrollCore` |
| `Sources/ScrollTiming` | Display-linked frame scheduling and timer fallback | None |
| `Sources/SmoothWheelAppCore` | Production engine coordinator, settings/lifecycle integration, native UI, optional diagnostics | `ScrollCore`, `ScrollEvents`, `ScrollTiming` |
| `Sources/SmoothWheel` | Thin executable entry point | `SmoothWheelAppCore` |

The dependency graph has no edge from engine modules back to the UI/coordinator. Keep shared motion logic in ScrollCore rather than duplicating it in controls or tests. Put target identity and routing policy in ScrollEvents, and scheduling mechanics in ScrollTiming; the coordinator connects them to settings and native event delivery.

Preserve existing state ownership and lifecycle contracts when crossing module boundaries. Input/frame callbacks stay bounded; asynchronous resolution and diagnostic writing must not block them. The detailed invariants are in [AGENTS.md](../AGENTS.md).

### Saved presets

`SavedScrollPreset.swift` defines the configuration value, stable identity, names, and validation. `SavedPresetStore.swift` owns one bounded, versioned UserDefaults collection and selection metadata. `AppDelegate` owns that store and applies a selected configuration through the existing engine settings/cancellation path. The current scalar settings remain the source used at launch; saving or managing a preset does not enable smoothing or change exclusions.

`SettingsWindowController` owns presentation, background input isolation, and focus restoration. `PresetLibraryController` presents built-in and saved choices. `PresetManagerController` tracks a record selected for Rename or Delete independently of the active selection. `PresetNameController` handles naming and validation feedback. `PresetDeleteController` presents the named confirmation. Both dialog controllers use the Soft Form `DesignAlertPanel` through the existing settings overlay. Storage rules remain outside view construction and input processing.

`SettingsMotion` handles UI-only fades and row positioning within SmoothWheelAppCore. It animates the original AppKit backing layers and retains at most one departing presentation and one departing row. `SettingsSurface` isolates outgoing views from hit testing, key equivalents, and accessibility. The window controller transfers logical ownership and the first responder immediately. Transition cleanup belongs to the current exit for each slot, so an interrupted exit cannot remove a reactivated surface. Storage operations commit before UI feedback runs. The render-only switch transition samples its displayed knob position and follows the committed engine or settings state.

## Supporting structure

| Path | Purpose |
| --- | --- |
| `design/tokens/soft-form.json` | Shared Soft Form design-token source |
| `Sources/SmoothWheelAppCore/DesignTokens.swift` | Generated native tokens; regenerate using `scripts/generate-design-tokens.py` |
| `Sources/SmoothWheelAppCore/DesignSystem.swift` | Reusable native surfaces, buttons, switches, sliders, and preset control |
| `Resources` | App bundle metadata and brand assets |
| `Tests/ScrollCoreTests`, `Tests/ScrollEventsTests`, `Tests/ScrollTimingTests` | Tests for their corresponding production modules |
| `Tests/SmoothWheelAppCoreTests` | Production-coordinator regressions, measurements, diagnostics, and UI snapshots |
| `Tests/SmoothWheelAppCoreTests/Snapshots` | Reviewed semantic/raster baselines and routing replay snapshot |
| `scripts` | Build support, token generation, validation, measurements, and source packaging |
| `docs/plans` | Feature proposals, review decisions, measurable criteria, and actual results |
| `artifacts` | Generated test, coverage, and performance evidence; ignored by Git |
| `.github/workflows/ci.yml` | Existing test, measurement, build, and evidence pipeline |

## Planning and review requirements

For each change, map files to responsibilities, identify consumers and dependency direction, and choose the matching test targets. Keep a new feature inside existing modules when their responsibilities fit. New targets, dependencies, languages, or shared components require a rationale in the reviewed proposal; implementation must not silently introduce a parallel architecture.

Follow [the implementation workflow](IMPLEMENTATION.md), [the design system](../design/README.md), and [testing and measurement](TESTING.md). Update this map when an approved structural change lands. The private website and public Homebrew tap are separate repositories; app code and public source archives must remain independent of private website files.
