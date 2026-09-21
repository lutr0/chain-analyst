# Smart-contract audit report

> Maintain this one report for the request. Replace bracketed fields with observed evidence; use `unknown`, `blocked`, `not run`, or `not applicable` with reasons rather than fabricated values. This report is not a security certification.

## Scope and conclusion

- Request / report ID: [stable identifier]
- Report path / started / last updated (UTC): [values]
- Requested depth and limits: [audit, scoped review, remediation verification; user exclusions]
- Target repository / project / contracts / callers: [scope]
- Out of scope: [paths, behaviors, dependencies, environments]
- Edit authorization: [read-only / harness-only / specified production remediation]
- Automated gate: [passed / failed / blocked / not run; reasons]
- Source-review completeness: [completed within scope / partial / blocked; reasons]
- Confirmed open risks and remediation outcome: [summary with finding links]
- Residual risks and unresolved assumptions: [summary]
- Conclusion: [bounded claim; green tools do not establish security]

## Snapshot and prior context

| Item | Observed value | Immutable evidence |
|---|---|---|
| Branch or detached HEAD | [value] | [artifact] |
| Commit | [full hash] | [commit-pinned link] |
| Dirty tracked / untracked paths | [paths or observed clean] | [status artifact] |
| Reviewed dirty-source identity | [sanitized patch / file hashes] | [artifact + digest] |
| Baseline commit and prior report | [identity or unavailable] | [pinned links] |
| Latest resolution / issue-tracker context | [identity and relevance] | [pinned links] |
| Snapshot changes during request | [before/after identity or none] | [artifact] |
| Synchronization | [not performed; or explicitly authorized action/result] | [artifact] |

No automatic pull, checkout, commit, or push is implied. Record each tested snapshot separately if authorized edits changed the source.

## Environment and evidence index

- Working directory / platform: [values]
- Foundry / compiler / analyzer / mutation tool versions: [observed versions or missing]
- Effective profile, configuration, test exclusions, FFI/build-hook policy: [values]
- Dependencies / remappings: [pinned versions and evidence]
- Fork network / chain ID / pinned block: [values or not applicable]
- Credentials / private data handling: [sanitized artifacts; never include secret values]

| Artifact ID | Purpose / run / snapshot | Immutable path or URL | Digest | Captured UTC |
|---|---|---|---|---|
| [ID] | [raw log, configuration, source snapshot, structured output] | [non-overwritten artifact] | [algorithm:value] | [time] |

Do not rely solely on a mutable `latest` directory or branch URL. Keep raw evidence from previous runs when the report is updated.

## Commands and gate results

Record actual commands, not suggested commands. Use a row for every attempt, including failed or unavailable checks. Counts are `unknown` when output is missing, not zero. The evidence runner does not perform source review or issue a final verdict.

| Check / run | Exact command and working directory | Snapshot / config | Exit code | Status and reason | Passed | Failed | Skipped | Artifact IDs |
|---|---|---|---|---|---|---|---|---|
| Snapshot | [actual command] | [identity] | [code] | [status] | N/A | N/A | N/A | [IDs] |
| Evidence runner | [actual command] | [identity] | [code] | [status] | N/A | N/A | N/A | [IDs] |
| Format check | [actual `forge fmt --check` invocation] | [identity] | [code] | [status] | N/A | N/A | N/A | [IDs] |
| Full unfiltered suite | [actual `forge test --force` invocation] | [identity] | [code] | [status] | [count] | [count] | [count] | [IDs] |
| Coverage | [actual invocation or not run] | [identity] | [code] | [status] | [if reported] | [if reported] | [if reported] | [IDs] |
| Static analysis | [actual invocation or not run] | [identity] | [code] | [status] | N/A | N/A | N/A | [IDs] |
| Remediation subset | [actual selector/command or not available] | [identity] | [code] | [status] | [count] | [count] | [count] | [IDs] |
| Positive regression | [actual invocation or not run] | [pre/post identity] | [code] | [status] | [count] | [count] | [count] | [IDs] |
| Mutation | [observed supported invocation or not run] | [identity] | [code] | [status] | N/A | N/A | N/A | [IDs] |

The remediation subset and positive regressions supplement, never replace, the full suite. Formatting failure, an unresolved skipped test, or an unperformed required check blocks the full gate. Record check failure separately from aggregate gate blockage.

### Skips, exclusions, and explicit scope decisions

| Test / check / exclusion | Observed reason | Explicit project decision, owner, and evidence | Security impact / remaining limitation | Gate effect |
|---|---|---|---|---|
| [name] | [reason] | [decision or absent] | [impact] | [blocked / documented exception / scoped out] |

### Remediation subset selection

- Selector and resolved current test names: [values/evidence]
- Finding IDs omitted from the selector, and why: [values]
- Harness/test mapping documents updated or intentionally unchanged: [paths/rationale]

## Findings and remediation matrix

Keep every confirmed, review, deferred, accepted, partial, and fixed/resolved finding visible. Acceptance requires an explicit project decision. Preserve classification history; do not delete resolved rows.

| ID | Prior → current classification | Severity / rationale | Contract:function and root cause | Exploit prerequisites / impact | Resolution / residual behavior | Current proof or test and observed result | Project decision / owner | Artifact IDs |
|---|---|---|---|---|---|---|---|---|
| [stable ID] | [classification; fixed if proven] | [severity] | [pinned source] | [path] | [status] | [test/triage/source proof/decision] | [reference] | [IDs] |

### Positive regression evidence

| Finding | Safe behavior asserted | Pre-fix failure evidence or why unavailable | Post-fix execution evidence | Remaining limitation |
|---|---|---|---|---|
| [ID] | [observable property] | [artifact] | [artifact] | [none or limitation] |

A passing exploit reproduction is not a positive regression proving a fix. Link remaining exploit reproductions to open or explicitly accepted finding rows.

## Fresh-eyes source review

- Baseline-to-current delta and changed production roots: [paths and pinned diff]
- High-risk callers inspected beyond changed lines: [paths]
- Review performed despite green gates: [actual review scope, not a checkbox claim]

| Surface / pinned source ranges | High-risk question / method | Assumptions and dependency boundaries | Outcome | Finding or evidence |
|---|---|---|---|---|
| [surface] | [accounting, privilege, delegatecall, queue/claim, slippage, token boundary, emergency, fee, etc.] | [assumptions] | [confirmed / accepted-residual / no newly confirmed issue within inspected scope] | [IDs] |

### Read-only lens coverage

| Lens | Owner / manually covered / unavailable | Disjoint assigned surfaces | Observations and limitations | Evidence |
|---|---|---|---|---|
| Accounting | [value] | [scope] | [result] | [links] |
| Access | [value] | [scope] | [result] | [links] |
| Execution | [value] | [scope] | [result] | [links] |
| Economics | [value] | [scope] | [result] | [links] |
| Integrations | [value] | [scope] | [result] | [links] |
| Evidence | [value] | [scope] | [result] | [links] |

### Deduplication and rejected candidates

| Candidate / originating lens | Contract:function / root cause | Canonical finding or rejection | Technical reason / counterevidence |
|---|---|---|---|
| [candidate] | [identity] | [ID / rejected] | [reason] |

## Static-analysis triage

- Tool/version/configuration and baseline comparability: [values]
- Current raw / unique finding counts: [counts or unknown]
- Prior raw / unique counts and pinned baseline: [counts/evidence or unavailable]
- Count and detector-class deltas: [changes; explain configuration-driven differences]

| Detector / source site | Raw occurrences / unique root causes | Reachability and manual triage | Finding / accepted rationale / rejected reason | Evidence |
|---|---|---|---|---|
| [class] | [counts] | [assessment] | [link] | [artifact] |

Untriaged warnings remain deferred work, not confirmed vulnerabilities or resolved findings.

## Coverage

| Metric | Raw covered / total | Raw percentage | Excluded covered / total | Adjusted covered / total | Adjusted percentage | Artifact |
|---|---|---|---|---|---|---|
| Lines | [counts] | [value] | [counts or none] | [recomputed counts or N/A] | [value or N/A] | [link] |
| Functions | [counts] | [value] | [counts or none] | [recomputed counts or N/A] | [value or N/A] | [link] |
| Branches | [counts] | [value] | [counts or none] | [recomputed counts or N/A] | [value or N/A] | [link] |

| Excluded file/range and metric | Covered / total contribution | Reason | Explicit acceptance / scope decision | Residual risk |
|---|---|---|---|---|
| [range] | [counts] | [reason] | [evidence] | [impact] |

Adjusted covered = raw covered minus excluded covered; adjusted total = raw total minus excluded total. Do not relabel adjusted percentages as raw. Explain zero denominators, incompatible scopes, or unavailable measurements rather than inventing percentages.

## Mutation outcomes

- Scope decision: [requested / not requested / explicitly excluded]
- Installed capability, version, and supporting help/documentation evidence: [values; unsupported is a valid outcome]
- Baseline suite result and snapshot: [evidence]
- Exact command, selected source/operators, seed and configuration: [observed values or not run]
- Result status: [completed / failed / blocked / unsupported / not run]
- Tool category definitions and score denominator: [values; no invented CLI or category mapping]

| Tool-reported outcome | Count or unknown | Artifact / interpretation |
|---|---|---|
| Killed | [count or N/A] | [evidence] |
| Survived | [count or N/A] | [evidence] |
| Timeout | [count or N/A] | [evidence] |
| Invalid / non-compiling | [count or N/A] | [evidence] |
| Other / excluded | [tool label and count or N/A] | [reason] |

| Surviving mutant / source | Behavioral significance | Equivalent / excluded rationale, if established | Test gap / finding / decision | Evidence |
|---|---|---|---|---|
| [ID] | [assessment] | [reason or unresolved] | [action] | [artifact] |

A survivor is a triage input, not automatically a vulnerability. An unsupported or unexecuted mutation run has no observed score.

## Changes, backlog, and limitations

| Changed path | Production / harness / report | Authorization and purpose | Verified snapshot / evidence |
|---|---|---|---|
| [path] | [type] | [scope] | [link] |

| Outstanding work | Finding / uncovered surface | Blocker or reason deferred | Owner / explicit decision |
|---|---|---|---|
| [item] | [link] | [reason] | [value] |

- Assumptions not independently verified: [list]
- Evidence unavailable or not rerun after edits: [list]
- Production-edit boundary respected or explicitly expanded: [details]
- Final bounded conclusion: [separate gate status, review scope, and residual risk; no security certification]
