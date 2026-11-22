# Feature plan: <short name>

Copy to `docs/plans/YYYY-MM-DD-short-name.md`. Replace the prompts; remove sections that do not apply with a short reason. Follow [the workflow](../IMPLEMENTATION.md).

## Status and scope
- Request / issue:
- Design review: draft
- Implementation: planned
- User acceptance: pending
- Automated verification: pending
- Physical validation: pending / not applicable (reason)
- Publication: not requested
- In scope:
- Non-goals:

## Behavior and acceptance criteria
Trigger and current behavior:

Desired behavior and user benefit:

Define thresholds before implementation. For behavior, use exact outputs/states/sequences; for timing or visual comparisons, include units and tolerances. Add success, failure/fallback, and preserved-regression criteria.

| ID | Scenario and metric / exact assertion | Baseline / current behavior | Target and tolerance | Method / workload / evidence artifact |
| --- | --- | --- | --- | --- |
| AC-1 | | | | |
| AC-2 | | | | |
| AC-3 | | | | |

Intentional contract/default changes, if any:

## Design proposal and approval

- Proposal revision:
- Visual mockup/prototype link (UI) or behavior/technical proposal (nonvisual):
- Existing design-system tokens and components reused:
- Proposed shared-system extensions, if any (require review):
- Important states and interaction examples:
- Tradeoffs / choices for review:
- Review request sent:
- Requested revisions and responses:
- Approved revision and artifact link:
- User approval date and short quote/reference (or explicit review waiver): **Pending**

**Gate:** stop before production implementation until this proposal is approved or review is explicitly waived. Material changes return to review.

## Evidence and diagnosis
- Reproduction / production-path regression:
- Baseline and measurement method, if performance is involved:
- Known facts versus hypotheses:
- Missing information / unresolved product decisions:

## Architecture and impact

Follow [ARCHITECTURE.md](../ARCHITECTURE.md) and the existing package structure. Explain a new layer/target/dependency before introducing it.
| Existing file/module | Responsibility / change | Dependency direction and affected consumers | Matching test target |
| --- | --- | --- | --- |
| | | | |

- State ownership and asynchronous cancellation / stale results:
- Event recipient, motion, passthrough, and lifecycle contracts affected:
- Settings defaults, persistence compatibility, and rollback:
- UI tokens, native controls, keyboard access, and appearances:
- Privacy, permissions, dependencies, and distribution impact:

## Implementation steps
1. Files/modules — change — verification.
2. Files/modules — change — verification.
3. Documentation and integration — change — verification.

## Verification plan
Select commands and scenarios using [TESTING.md](../TESTING.md). Do not claim an unrun check passed.

| Criterion ID | Check / command or physical sequence | Measurement method, units, sample count/repetitions, tolerance | Planned artifact |
| --- | --- | --- | --- |
| | Focused regression | | |
| | `./scripts/test.sh` when applicable | | |
| | `./scripts/measure-engine.sh` when applicable | | |
| | `./build.sh` when applicable | | |
| | Physical-wheel scenarios when applicable | | |

## Measured results

“Tests passed” alone is insufficient. Populate this table with actual results and artifact links; leave unavailable measurements pending and explain why. Each acceptance criterion must have an outcome.

- Source revision / build mode:
- OS / hardware / app versions:
- Settings / workload / sample count or repetitions:

| Criterion ID / metric | Baseline | Agreed target and tolerance | Actual result (with units) | Pass / fail / pending / not applicable | Evidence link |
| --- | --- | --- | --- | --- | --- |
| AC-1 | | | | Pending | |
| AC-2 | | | | Pending | |
| AC-3 | | | | Pending | |

- Relevant coverage: covered/executable lines and percentage per affected module/file, plus remaining gaps:
- Relevant latency: samples and p50/p95/maximum, in matched release builds without coverage:
- Baseline versus changed measurements, with matched conditions:
- Snapshot changes inspected and reason for any re-recording:
- Skipped/unavailable checks and practical limits:

## Demonstration and acceptance

- Implemented screenshots/demo or behavior results:
- Differences from the approved proposal, if any:
- Acceptance requested:
- User acceptance date and short quote/reference: **Pending**
- Requested corrections:

## Rollout and completion
- Rollback / recovery:
- Documentation updated:
- Cross-repository follow-ups (website / Homebrew), if requested:
- Release version and verified links, only after publication:
- Acceptance criteria reviewed against the final diff:
- Remaining risks / follow-ups:
