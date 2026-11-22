# SmoothWheel project rules

These rules apply throughout this repository. Follow the user's authorized scope; a feature request does not by itself request installation, a public release, or website changes.

## Start here
- Follow [the implementation workflow](docs/IMPLEMENTATION.md): brief → design/proposal → user review → explicit approval → implementation → verification and demo → acceptance. Use its small-change path only within already approved scope.
- Create or update a plan from [the feature template](docs/plans/TEMPLATE.md) for new features and nontrivial behavior/design changes. Maintain one plan per change and record the reviewed proposal and approval.
- Inspect the working tree first. Preserve unrelated edits and keep each change focused. Use graft when available; otherwise use targeted searches and reads.
- Define measurable acceptance criteria before implementation: metric or observable assertion, baseline, target/tolerance, method, and evidence artifact. Record actual results against those criteria; a test-pass count alone is insufficient.

## Approval before implementation
- Present a concrete visual design or prototype for UI work; for nonvisual work, present the intended behavior, examples, and technical approach. Link the proposal in chat and ask the user to review it.
- Stop before production implementation until the user explicitly approves that proposal. A feature request, silence, or an unanswered review request is not approval. Research, plans, and clearly separate mockups may continue.
- Approval covers the agreed scope across turns. Implement and test without asking again for routine choices. Return material changes to the design, behavior, or scope for review before implementing those changes.
- Skip this gate only if the user explicitly requests skipping review or has already approved the same proposal. Direct, small corrections within approved scope do not need a new design round.

## Architecture and engine
- Follow [the architecture and project structure](docs/ARCHITECTURE.md). Map affected files, responsibilities, dependency direction, and tests before implementation. Extend existing modules; justify any new layer, target, or dependency in the reviewed proposal.
- Input and frame callbacks must remain bounded: no synchronous Accessibility probes, process/window enumeration, disk/network I/O, or waiting on background work. Cache recipient identity; bound and coalesce asynchronous discovery; reject stale completions.
- Preserve the engine's documented main-run-loop state ownership. Do not introduce concurrent mutation or a queued backlog of synthetic frames.
- Preserve continuous trackpad and synthetic-event passthrough, shortcut/Option bypass, input direction and distance, responsive reversal, pointer position, and interruption/teardown behavior unless the feature intentionally changes a documented contract.
- Route exclusions using the event recipient, including inactive windows, overlays, and background document renderers. Preserve consistent native/smoothed routing within a burst and fail-open behavior for unresolved ownership.
- Fix the responsible layer. Avoid app-name exceptions, guessed phases, timing sleeps, or new polling loops as substitutes for an explained and tested cause.
- Prefer the existing Swift/AppKit stack. Rust or another dependency is allowed when a measured bottleneck or concrete capability justifies it; account for interoperability, packaging, and maintenance in the plan.

## UI, settings, and privacy
- Design from the existing [Soft Form system](design/README.md): reuse its tokens, typography, spacing, surfaces, and controls in mockups and production. Identify reused components in the proposal. Review a proposed system extension before introducing new styles; preserve native controls and accessibility preferences.
- Edit `design/tokens/soft-form.json` and run `python3 scripts/generate-design-tokens.py` for token changes; do not hand-edit generated `Sources/SmoothWheelAppCore/DesignTokens.swift`.
- Define defaults, validation, compatibility with saved settings, and rollback behavior when introducing state. Preserve user preferences during development checks.
- Keep the app local and free of unrequested telemetry. Diagnostics are opt-in; publish only reviewed aggregate data, never private content, process/app histories, credentials, or raw recordings.

## Verification and completion
- Use production `handle`/`tick` paths and injected dependencies for behavior regressions. Reproduce reported failures before fixing them where practical; do not build a second test-only engine.
- Follow [TESTING.md](docs/TESTING.md) for commands, coverage floors, timing budgets, and snapshot review. Do not weaken checks or re-record goldens merely to make a failure pass.
- Compare performance in matched release-mode runs without coverage. Report callback latency, frame intervals, probe time, and external rendering separately; do not infer user-visible smoothness from unit tests.
- Report expected versus actual results with units, tolerances, environment, sample/workload details, and artifact links. Include relevant coverage, latency, snapshot differences, and functional outcomes. Record skipped/unmeasurable checks as pending, failed, or not applicable with reasons. Documentation-only changes need link/diff checks, not a Swift build.
- Mark implementation, automated verification, physical validation, and publication separately. Never claim a blocked or unrun check passed.

## Distribution
- Follow [RELEASE.md](docs/RELEASE.md) when a release is requested. Use immutable versioned artifacts and update checksums and the developer Homebrew tap together.
- The current distribution is ad-hoc signed and not notarized. No paid Developer Program membership is assumed. Do not disable Gatekeeper, strip quarantine, or describe a successful signature check as notarization.
- The public app, private `SmoothWheel-Web` repository, and public `AntonMazur/homebrew-tap` are separate projects. Record cross-repository follow-ups without copying private website files into this repository.
