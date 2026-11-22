# Implementing a change

Use this workflow to turn a feature request or bug report into a focused, reviewable change. [AGENTS.md](../AGENTS.md) contains the project-wide constraints; [TESTING.md](TESTING.md) and [RELEASE.md](RELEASE.md) own the detailed check and release instructions.

## Default sequence

**Brief → design with our system + architecture and measurement plan → user review → approval → implement within the project structure → measure and demonstrate → user accepts.** Publish only when requested. The design review is a real stop before implementation, not an update sent while implementation continues.

## 1. Define the brief

For a new feature or nontrivial behavior/design change, copy [the template](plans/TEMPLATE.md) to `docs/plans/YYYY-MM-DD-short-name.md`. Keep one plan throughout the review and implementation.

- Describe the trigger, current behavior, desired outcome, and user benefit.
- Define measurable acceptance criteria, including failure/cancellation behavior, and state non-goals. Each criterion names a metric or exact observable assertion, baseline/current behavior, target and tolerance, measurement method, and evidence artifact. Set targets before implementation; explain when a baseline does not apply.
- Research affected production paths, callers, lifecycle, dependencies, and existing design-kit components. Record facts separately from hypotheses.
- For a bug, investigate the cause; for performance work, collect a baseline before proposing an optimization. Missing physical hardware is an evidence gap, not permission to claim success.

Use existing context for routine decisions. Ask only when an unresolved product choice would materially change the proposal. Check current primary documentation when an Apple API or Homebrew requirement is uncertain.

## 2. Create something reviewable

For UI work, prepare a visual mockup, annotated screenshot, or isolated interactive prototype showing the affected screen or flow. Include important states such as enabled/disabled, empty/populated, errors, and permission setup when relevant. Use the existing [Soft Form design system](../design/README.md) as the source of truth, including `design/tokens/soft-form.json`, generated `Sources/SmoothWheelAppCore/DesignTokens.swift`, and reusable controls in `Sources/SmoothWheelAppCore/DesignSystem.swift`. List the existing tokens/components used. Reuse established typography, spacing, colors, surfaces, and interactions instead of creating a separate style for each feature. If the system lacks a needed pattern, show the proposed extension for approval and add it to the shared system after approval. A prose description alone is insufficient when appearance is the decision being reviewed.

For a nonvisual feature, prepare a behavior and technical proposal: input/output examples, user-visible effects, relevant settings/defaults, affected modules, failure/fallback behavior, and how it will be measured or tested. An engine feature does not need an invented visual mockup.

Use [ARCHITECTURE.md](ARCHITECTURE.md) and `Package.swift` to map the change onto the existing project structure. Name affected files/modules, their responsibilities, dependency direction, consumers, and matching test targets in the proposal. Keep domain logic out of UI components and the executable entry point. Prefer extending existing modules; explain any necessary structural change and include it in review. Add numbered implementation steps, migration, state ownership, cancellation of stale work, and rollback when applicable. Propose the smallest complete change; Rust or another dependency needs a concrete capability or measured bottleneck and a clear integration boundary.

Keep exploration separate from production: mockups, plans, and research are allowed before approval; production feature implementation, wiring, and installation wait for approval. Do not hide completed feature work inside a prototype.

## 3. Send for review and wait for approval

Send the actual design/proposal in chat with a working artifact link or visible preview, the design-system components used, the architecture/structure impact, measurable success criteria, any important tradeoff, and a clear request for approval. Do not ask the user to approve an abstract promise to produce a design later.

Set review status to `awaiting review` and stop dependent implementation. If the user requests changes, revise the proposal and present the changed version for review. An unanswered request or elapsed time is not approval.

After explicit approval of that proposal, record the approved revision, artifact link, date, and a short quote or reference to the user's approval in the plan. Approval from an earlier turn remains valid for the same scope. A general request such as “add this feature” is not approval of a design that has not been presented. The user can explicitly waive review, for example, “skip design review and implement directly”; record that waiver instead of inventing approval.

For a large feature, the approved proposal may define several implementation increments; do not require another approval for each routine increment. If implementation reveals a material change to appearance, interaction, defaults, behavior, or agreed scope, present the revised proposal and wait for approval of that change. Continue unaffected approved work where possible.

Small documentation fixes, copy corrections, or implementation defects within an already approved design can use a lightweight path: make the requested correction and verify it. A new screen, changed flow, or different interaction is not a small-change exception.

Select verification before coding:

| Change | Required evidence |
| --- | --- |
| Documentation or copy | Diff, valid local links, consistency with actual behavior; inspect UI if visible text/layout changes |
| Native UI or design tokens | Relevant control/interaction checks; `./scripts/test.sh` for design checks and UI baselines on the supported host; `./build.sh` for shipped Swift changes |
| Motion, events, routing, frame clock, or lifecycle | Production-path regression tests, `./scripts/test.sh`, `./scripts/measure-engine.sh`, `./build.sh`, and the affected physical-wheel scenarios |
| Settings or permissions | Defaults/persistence/error-path coverage, affected UI snapshots, full suite and build, and a live check when OS approval or real lifecycle behavior is involved |
| Packaging or Homebrew | Artifact metadata, architecture, checksum, signature status, and isolated install/removal checks; exercise upgrade behavior for changes to upgrades |
| Public release | All release checks in [RELEASE.md](RELEASE.md), reviewed public artifacts, and verified download/cask metadata |

Add focused checks where they answer a risk the existing suite misses. Do not add tests that merely duplicate implementation or tests for every wording edit. CI supplies macOS-specific snapshot checks when the local OS cannot run those baselines; keep that result pending until CI runs.

## 4. Implement the approved proposal

Confirm the plan records approval or an explicit review waiver before editing production behavior. Implement the approved design and interactions faithfully.

Implement in the approved module/file structure and dependency direction. Change the responsible layer first, then connect settings/UI and other consumers. Keep hot paths bounded and preserve the contracts in AGENTS.md. Use the same shared tokens and components shown in the approved design; do not hand-style a parallel implementation. Do not mix unrelated refactors into a fix. Update ARCHITECTURE.md when an approved structural change lands.

Run focused checks while iterating. When evidence changes the diagnosis, update the plan and remove abandoned branches, unused compatibility paths, and temporary instrumentation. Return material changes to the approved design, behavior, or scope to the review stage before implementing them. Preserve unrelated working-tree changes.

## 5. Measure the result against the agreed criteria

“Tests passed,” a screenshot alone, or a coverage percentage alone does not establish that a feature works. Fill in the plan's results table for every acceptance criterion: baseline → agreed target/tolerance → measured actual → pass/fail → evidence. For functional behavior, an exact expected-versus-actual event, state, count, or sequence is a measurable result; do not invent a timing target for a wording edit.

Record revision/build mode, OS/hardware, settings, workload, sample count or repetitions, units, and commands where relevant. Link machine-readable reports or comparison artifacts; keep private raw evidence local. No measurement means pending or an explained not-applicable result, not a pass. Capture evidence during verification rather than adding unrequested production telemetry.

Use relevant evidence from the existing suite:

| Area | Measure and record | Evidence / policy |
| --- | --- | --- |
| Functional correctness | Exact output direction/distance, routing decisions, transitions, unchanged passthrough fields, or expected state; identify tested and missing scenarios | Production-path tests and routing replay snapshots under `Tests/`; failure evidence under `artifacts/tests/` |
| Callback/frame work | Samples, p50/p95/maximum in milliseconds for native, smoothed, background-renderer, and emission paths; baseline versus changed build when claiming improvement | `artifacts/performance/callbacks.json`; current `scripts/check-performance.py` gate requires at least 1,000 samples per path and p95 ≤ 2 ms |
| Coverage | Covered/executable production lines and percentage for affected files/modules, compared with existing floors; identify uncovered behavior | `artifacts/coverage/summary.json` and `summary.md`; floors in TESTING.md and `scripts/coverage-report.py` |
| UI/design | Semantic control values/bounds and raster difference statistics against reviewed baselines; design-token generation and contrast checks | Actual/expected/difference artifacts in `artifacts/tests/`; tolerances and appearances in TESTING.md |
| Real-wheel behavior | Fixed reproduction sequence, app/OS/mouse/settings, observed result for each scenario, and explicit subjective reports; distinguish visual observations from instrumented timing | Opt-in local diagnostics plus the physical validation record; never label emission intervals as external-app FPS |

Existing gates are minimum regression checks. Feature-specific criteria must also answer the user's actual problem; passing a 2 ms callback budget does not prove a reported landing shake is fixed. Do not lower thresholds after seeing results or claim improvement without a comparable baseline. Review changed UI against both the approved design and the existing system.

Run the selected required checks and review their artifacts. Preserve the existing coverage and timing gates from TESTING.md. Review actual/expected/difference images and semantic JSON before intentionally updating UI snapshots. Never auto-accept a CI mismatch.

For performance work, use matched optimized builds with the same workload, settings, hardware, and sampling method. Keep raw evidence local and record the commands and relevant aggregate results in the plan. A broad timing-budget pass is a regression check, not proof of a speedup. Local event emission is not another application's rendering FPS.

For engine changes, run the applicable real-wheel sequence with one smoothing utility active and fixed speed/smoothing/zoom:

- Short steps, sustained scrolling, stopping, reversal, and horizontal input where supported.
- Trackpad passthrough, Option bypass, scrolling shortcuts, click/key interruption, and sleep/wake when affected.
- Native scrolling in an excluded app, immediate transition to an included windowed app, and the system Applications overlay above the excluded app.
- Ordinary Notes content and an embedded document when recipient handling changes.
- Gmail in Chrome at 100% zoom when motion/landing changes; record symptoms without inventing a browser-specific cause.
- Multiple displays and the macOS 13 timer fallback when clock selection changes, or explicitly list these as untested.

Record app/OS/mouse versions and whether the observation is automated or physical. Use neutral test content. Do not refresh Accessibility approvals or replace the user's installed app as an incidental test step; do it only within the user's authorized scope.

If a required live check needs the user, leave physical validation pending and ask for the specific sequence after completing all independent implementation and checks. Do not describe the feature as physically verified before the result arrives.

## 6. Demonstrate the result and obtain acceptance

Review the final diff against both the approved proposal and acceptance criteria. Update documentation and the plan with results and limitations. Present the implemented result with screenshots or a demo for UI changes, and concrete results for nonvisual changes. Show the expected-versus-actual measurement summary and evidence links, explain any unmet criterion or missing physical evidence, and request final acceptance. Keep the state `awaiting acceptance` until the user accepts it. Corrections within the approved design continue directly; a material redesign returns to stage 3.

Track these states independently:

- Design review: draft / awaiting review / changes requested / approved / explicitly waived.
- Implementation: planned / in progress / implemented.
- User acceptance: pending / awaiting acceptance / accepted / changes requested.
- Automated verification: pending / passed / failed, with skipped checks named separately.
- Physical validation: pending / passed / failed / not applicable, with rationale.
- Publication: not requested / pending / published, with a version or link only after verification.

A feature can be implemented while physical validation or publication remains pending. Do not turn that partial state into a claim that the issue is fully resolved.

## 7. Publish when requested

Final feature acceptance is not by itself a release request. When publication is requested, follow RELEASE.md. Building a ZIP is not a GitHub release. Keep existing release assets immutable, publish only reviewed public files, and coordinate the app download, developer-maintained tap, and separate website within the requested scope. Do not claim notarization or silently buy a membership; the current free distribution uses ad-hoc signing and documents first-launch approval.
