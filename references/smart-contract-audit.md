# Smart-contract audit workflow

Load this reference only for an audit or remediation-verification request. It is not a prerequisite for a balance, ABI, price, transaction, or other narrow lookup. A security-related word alone does not expand a lookup into an audit.

## Select depth and scope

- **Lookup:** answer one bounded fact with the smallest read-only query; do not load the audit workflow or run its gates.
- **Analysis:** reconstruct behavior or combine evidence for an explanation. Load only the chain/API references needed; a transaction investigation is not automatically a contract audit.
- **Audit:** follow this workflow for a requested security review, audit rerun, or remediation verification. Honor explicit limits on contracts, findings, tools, network access, and edits. Label a scoped review as scoped; do not claim a full audit gate when excluded work remains.
- **Clarify:** ask the smallest question when the target, intent, or permission is materially ambiguous. Do not start expensive gates or disclose private source while waiting.

Use the local decision tree first. Optional Jev planning is advisory: a plan cannot expand the user's scope, authorize external disclosure, or supply commands to execute. Do not install or upgrade tools automatically.

## 1. Snapshot before evidence collection

Identify the repository and project root, contracts and callers in scope, baseline report/commit, harness locations, allowed edits, and requested deliverable. Capture local state without fetching or pulling:

```bash
git status --short --branch
git branch --show-current
git rev-parse HEAD
```

Record detached HEAD explicitly, dirty tracked and untracked paths, and the relevant local diff. A commit alone does not identify a dirty source tree: preserve a sanitized patch or content hashes for reviewed files and generated evidence. Never overwrite existing work. Do not pull, checkout, commit, push, install, upgrade, or send transactions automatically. A user-authorized synchronization changes the snapshot and requires recording both states before using subsequent results.

Locate the latest relevant audit report, resolution notes, issue tracker, test mappings, and static-analysis baseline. Check that each belongs to the source under review; dates or a mutable `latest` path are not proof. Rebuild the remediation context from current source and tests rather than trusting old passing results.

## 2. Collect distinct gate evidence

For Foundry setup, test/coverage details, and mutation capability, load [foundry-testing.md](foundry-testing.md) only when that work is needed. Record installed versions and the actual configuration/profile, compiler, fork chain/block, dependency versions, and capability output used. Missing tools block their checks; never substitute stale reports or silently upgrade.

The evidence runner interface is:

```text
bash scripts/audit-contracts.sh <project-dir> <new-artifact-dir> [--mutation <source-path>] [--slither]
```

Run it from the skill root or use an absolute path to the script. Choose a new artifact directory for each evidence run; retain earlier evidence without overwriting it. The script collects evidence only. It does not perform source review, classify vulnerabilities, or deliver a final audit verdict. Inspect its logs and results rather than interpreting process success as security approval. Review untrusted project configuration first: local tests, build hooks, FFI, and analyzers can execute project-controlled code. Use an appropriately isolated environment without production credentials.

Keep these checks separate in the report:

| Check | Required interpretation |
|---|---|
| Formatting | `forge fmt --check`; a failure blocks the full gate even if tests pass. Do not auto-format user source. |
| Full tests | Unfiltered `forge test --force`, with exact passed/failed/skipped counts. Record effective configuration, including exclusions, rather than hiding filters in profiles or environment variables. |
| Coverage | Record the exact command, exit status, included scope, raw counts/percentages, and artifact. Instrumented coverage is a separate run, not the full-test gate. |
| Static analysis | Request `--slither` for a full audit gate. Record raw and deduplicated counts, detector deltas, exclusions, and manual triage. Analyzer success does not mean zero vulnerabilities. |
| Remediation subset | Run the project's existing selection when available; record the exact command and counts. This supplements, never replaces, the full suite. |
| Mutation | Run only when requested/in scope and the installed capability is established. Link the Foundry reference; do not guess CLI syntax. |

Any skipped Foundry test blocks the gate unless the report names that test and cites an explicit project decision accepting the omission, including rationale and impact. A missing tool, failed check, absent output, unresolved skip, or unperformed required step is not a pass. Distinguish **failed**, **blocked**, **not run**, and **not applicable**. Explicit user exclusions remain visible and narrow the reported conclusion; they are not successful checks. An empty test collection is not evidence of a complete suite.

## 3. Reconcile every finding and remediation

Maintain stable project finding IDs without importing IDs or naming schemes from another project. Map every prior and new finding to current source, evidence, and disposition:

- **Confirmed:** a reproducible source-level bug or reachable exploit path; state prerequisites and impact.
- **Review:** observed behavior whose security or product classification remains unresolved.
- **Deferred:** incomplete investigation or verification backlog, including untriaged static analysis or unavailable mutation work.
- **Accepted:** an explicit project decision, with owner, rationale, and supporting evidence; the auditor cannot silently accept risk for the project.
- **Partial:** only part of the issue is addressed, or operational mitigation remains instead of complete code remediation.

Track fixed/resolved findings too, with their prior classification and current resolution. Keep accepted, deferred, and partial risks visible across reruns. Link each row to a current test, source proof, static-analysis triage, earlier framework reference where still applicable, or explicit project decision. A historical test reference alone does not prove current execution.

For a fix, require a **positive regression** that asserts the intended safe behavior and would fail before the fix. A passing pre-fix exploit reproduction does not prove remediation. Record actual pre/post evidence or explicitly state when a pre-fix run is unavailable. Link remaining exploit reproductions to issue-tracker entries. Keep existing project test selectors, harness documentation, and the report matrix aligned when tests or finding mappings change; confirm a remediation selector includes the intended tests rather than only recording a green command.

## 4. Fresh-eyes source review

Review high-risk source every audit cycle, including remediation-only deltas, even when every automated check is green. Compare the baseline to the current snapshot, identify changed production roots and callers, then inspect assumptions independently of earlier issue labels. If no trustworthy baseline exists, say so and review the scoped current source.

Use disjoint **read-only** lenses when independent review capacity is available. Assign a primary owner per surface/root cause; share boundary observations rather than duplicating entire reviews. These neutral lenses are independently written for this workflow:

| Lens | Primary questions |
|---|---|
| Accounting | Do assets, shares, liabilities, pending credits, and fees reconcile through all state transitions? Are units and precision consistent? |
| Access | Are initialization, roles, upgrades, pause controls, allowlists, and disabled hooks enforced at every reachable entry point? |
| Execution | Do external calls, reentrancy boundaries, delegatecall identity/storage, queue transitions, and claim ordering preserve intended state? |
| Economics | Can donations, rounding, slippage, stale prices/epochs, or asymmetric entry/exit rules transfer value outside the stated model? |
| Integrations | Do token behavior, adapter/bridge amounts, return-data decoding, and dependency trust assumptions match actual external interfaces? |
| Evidence | Do test selection, coverage scope, static-analysis triage, remediation assertions, and report claims match the captured snapshot and logs? |

Include emergency/admin paths and their differences from ordinary execution. For each reviewed surface record a confirmed issue, accepted/residual behavior with rationale, or no newly confirmed issue within the inspected scope. Record which lenses ran, which were manually covered, and which were unavailable. Missing review capacity is a limitation, not a completed review.

Deduplicate candidates by contract, function, and root cause; link all contributing evidence to the canonical finding. Preserve rejected candidates with a short technical rejection reason. Do not upgrade a detector warning or speculative lens result into a confirmed vulnerability without checking reachability, assumptions, and proof.

## 5. Respect the edit boundary

A read-only review makes no source changes. A harness-only audit may change authorized tests, mocks, fuzz/invariant cases, and helpers to close a concrete evidence gap; it must not edit production contracts. Production remediation requires explicit scope authorization. Do not add tests merely to increase counts: exercise the actual boundary, transition, invariant, or error implicated by the finding. Report every changed path and whether it is production, harness, or reporting work.

After an authorized fix, collect fresh full-gate evidence as well as the focused regression; preserve the earlier evidence. If further execution is blocked, report that limitation instead of closing the finding from code inspection alone.

## 6. Maintain one report per request

Use [the audit report template](../assets/audit-report-template.md). Choose one report path for the request and update it throughout the work, correcting superseded conclusions in place. Multiple evidence runs may have distinct immutable artifact directories; do not create a new final report for each pass unless requested.

Include exact commands, working directories, versions, timestamps, exit/status distinctions, test counts, snapshot identity, reviewed surfaces, assumptions, and immutable evidence links. Prefer content-hashed local artifacts or commit-pinned links over mutable `latest` URLs. Sanitize credentials and private endpoints before publication; identify redactions without exposing secret values.

Report raw line/function/branch coverage separately from any adjusted metric. Each exclusion needs a path/range, reason, raw covered/total contribution, and explicit acceptance. Recompute adjusted numerator and denominator; never present adjusted coverage as raw or turn missed branches into invented vulnerabilities. Uncovered branches are a harness backlog unless a concrete unsafe path is established.

For mutation work, report supported capability/version, exact invocation if run, selected source/operators, baseline, killed/survived/timeout/invalid or other tool-reported categories, exclusions, and surviving-mutant triage. If unsupported, blocked, or not requested, say so; do not invent a zero count, CLI, score, or successful run. Preserve the tool's category definitions and disclose the denominator for any score.

Conclude separately on the automated gate, review completeness, and open/residual risks. A passing gate or no newly confirmed issue is **not a security certification**, nor proof that exploitable behavior is absent.

## Provenance

Adapted from the Sophon `foundry-security-audit` workflow: evidence gates, remediation mapping, independent source review, and report continuity. The review lenses are independently phrased; no text from the separately licensed Trail of Bits lens companion is included.
