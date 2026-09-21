# Foundry testing and external mutation evidence

Load this reference when Foundry checks or mutation testing are actually in scope. Automated evidence is not a security certification and does not replace contract review.

## Tool requirements and opt-in setup

Use a reviewed Foundry release providing `forge fmt`, `forge test`, `forge lint`, and `forge coverage`. Record the actual installed versions and command capabilities for each run rather than treating a historical verification result as a compatibility guarantee.

The mutation log adapter requires **Slither 0.11.6** because its output is not a stable machine-readable results protocol. A compatible standalone `solc` must also be on `PATH`: Forge's managed compiler alone is insufficient for Slither's direct compiler calls. Resolve the compiler against the project's pragma and configuration.

Official sources:

- [Foundry installation](https://getfoundry.sh/introduction/installation/)
- [Forge command reference](https://getfoundry.sh/forge/reference/)
- [Slither 0.11.6](https://github.com/crytic/slither/releases/tag/0.11.6)
- [Mutation tool instructions](https://github.com/crytic/slither/blob/0.11.6/docs/src/tools/Mutator.md)
- [Mutation runner implementation](https://github.com/crytic/slither/blob/0.11.6/slither/tools/mutator/__main__.py)
- [Per-mutant compilation and testing](https://github.com/crytic/slither/blob/0.11.6/slither/tools/mutator/utils/testing_generated_mutant.py)

Installation is an explicit user action. After selecting a Foundry release using the official installation guide, the matching Slither adapter can be installed with:

```bash
uv tool install slither-analyzer==0.11.6
```

The evidence runner never installs tools. Missing `forge`, `slither`, `slither-mutate`, `solc`, or another required utility blocks its check. Do not silently upgrade dependencies, select a different compiler, or reuse stale artifacts. Record `forge --version`, `slither --version`, and `solc --version`.

Mutation in this workflow uses the separate `slither-mutate` executable with Forge as its test command; the runner does not invoke or assume a native `forge mutate` command.

## Baseline checks and reproducibility

Run commands from the reviewed Foundry project root, after reviewing configuration and execution permissions:

```bash
forge fmt --check
forge test --force
forge lint
forge coverage --report summary --report lcov
```

Use each installed command's `--help` for options before adapting a workflow. Formatting is check-only: do not rewrite source automatically. Lint findings need their own triage and are not a replacement for Slither or manual analysis. A clean test exit is insufficient if there were no tests, failures, skips, filters, or unintended exclusions. Preserve logs, counts, command arguments, effective profile/configuration, tool versions, source snapshot, and fork chain/block. Coverage is an independently instrumented run, not the full-test gate. Distinguish unavailable tools, failed checks, blocked checks and explicitly excluded checks.

For fuzzing, record and reuse a deterministic seed rather than silently choosing a new seed on a rerun. For example, after confirming the installed flag with `forge test --help`:

```bash
forge test --force --fuzz-seed 0x0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef
```

Keep the project's configured fuzz runs, invariant runs/depth, failure policy, handlers, target selectors, and saved failure corpus visible. A short smoke run is not the configured full campaign. Invariant coverage depends on the configured handlers and reachable state transitions, not merely a large iteration count. Replay saved failures under the recorded source/configuration before treating a remediation as verified. Inspect corpus capabilities lazily with `forge fuzz --help` when corpus work is requested; do not invent corpus subcommands or assume syntax from another release.

### Raw and adjusted coverage

Retain the raw summary and LCOV artifact, command, scope, exclusions, and counts. Report line, branch, statement and function measurements separately where the tool supplies them. If an adjusted figure excludes generated code, mocks, interfaces or unreachable branches, retain the raw result and list every excluded file/region, rationale and numerator/denominator change. Label the adjusted result as an analysis, never overwrite raw coverage or imply a high percentage establishes security. Unsupported instrumentation/compiler configurations are blocked coverage evidence, not grounds to invent a number.

## Evidence runner interface

From the skill root (or use an absolute script path):

```bash
bash scripts/audit-contracts.sh <project-dir> <new-artifact-dir> [--mutation <source-path>] [--slither]
```

`--slither` requests static analysis; mutation is separately opt-in. Choose a new evidence directory outside the project with an existing parent. The runner does not install tools, synchronize repositories, broadcast transactions, fix source, or invoke model commands. Follow [smart-contract-audit.md](smart-contract-audit.md) for findings, remediation evidence, full-gate interpretation and report requirements.

The mutation helper can also be called directly:

```bash
MUTATION_TIMEOUT_SECONDS=300 bash scripts/mutate-contracts.sh \
  /path/to/project /path/to/new-mutation-evidence src/Contract.sol
```

The target is a nonempty existing project-relative `.sol` file or directory containing nonempty Solidity files. Flags, absolute source paths, `..` traversal and paths escaping the project are rejected. The project must include `foundry.toml`. `MUTATION_TIMEOUT_SECONDS` is an explicit integer from 1 through 999999 (default 300); it bounds the helper's baseline and is passed to upstream per-test mutation execution, not a bound on the whole campaign. Upstream runs another baseline without a timeout before mutating, so review or interrupt a hung campaign rather than interpreting silence as success.

### Source-write isolation, not a security sandbox

Slither mutates source files in place. The helper first copies inputs into a fresh disposable directory **outside the original project**, then runs the baseline and mutator only from that copy. It preserves `lib` and `node_modules`; it never silently drops dependencies just to make a copy cheaper. It rejects symlinks and special files in copied inputs instead of following links. This includes linked dependency trees and `node_modules/.bin` links: supply a reviewed, self-contained checkout with ordinary dependency files, rather than redirecting links to the original tree. It does not resolve dependencies automatically.

The copy explicitly excludes `.git`, `.env`, `.env.*`, `*.pem`, `*.key`, `.ssh`, `.aws`, `.npmrc`, `.netrc`, and directories/files named `out`, `cache`, `broadcast`, `coverage`, or `mutation_campaign`. The external artifact path cannot be included in the project copy. `copied-paths.nul` records included paths. These exclusions are conservative, not comprehensive secret detection. If the project needs an excluded input, prepare an appropriate self-contained checkout; do not silently reuse original outputs. Never run with production credentials in the environment.

Review project scripts, FFI, configuration, compiler settings, imports, remappings and absolute paths before execution. A copy is **not a security sandbox**: project-controlled code can access the host, network and absolute paths, and environment variables are inherited. The helper does not rewrite absolute remappings or pretend every Foundry project is supported. Slither's direct `solc` compilation can fail where Forge builds successfully, especially for imports/remappings or multiple compiler versions. Preserve the failure as blocked/failed evidence and resolve compatibility explicitly.

A trap removes only the helper-owned disposable directory after completion/failure/catchable interruption; original files are never restored or edited by the helper. It retains logs and campaign artifacts in the new output. Uncatchable termination such as SIGKILL may leave the disposable directory for manual inspection. Independent SHA-256 aggregates of original Solidity paths/content are recorded before and after execution, and a mismatch fails the result without overwriting concurrent user changes. These checks detect changes; they cannot sandbox malicious project code or prove unchanged non-Solidity files.

### Mutation command and evidence semantics

Inside the disposable project, the helper invokes:

```bash
slither-mutate ./src/Contract.sol \
  --test-cmd 'forge test --force' \
  --timeout 300 --output-dir /path/to/new-mutation-evidence/campaign \
  --verbose --comprehensive
```

The target and timeout reflect the validated inputs. Upstream appends `--fail-fast` to Forge tests internally. Its output directory is destructive, so the helper passes only a fresh `campaign` child of its exclusively created evidence directory; it never hands upstream an existing caller directory.

Before invoking the mutator, the helper requires a successful JSON baseline with recognized nonzero tests, zero failures and zero skips in the copy. It retains `baseline.json`, `mutation.log`, tool-version records, campaign artifacts, and `summary.json`; stdout is the same JSON summary. Configuration may still narrow discovery, so review the effective project test configuration independently.

Exit zero from upstream does **not** establish a successful mutation campaign: it can return zero after a failed baseline, no matching contracts, or caught internal exceptions. The helper requires a completion marker, actual individual mutation outcomes, at least one compiled/tested mutant, no observed timeout, and no detected error/no-test markers. Unsupported targets, incomplete or compile-only campaigns and ambiguous evidence are blocked; nonzero tool exits are failed. Both return nonzero from the helper. A completed campaign returns **`review_required`**, never `passed` or a security score.

Raw counts are taken only from explicit per-patch verbose `CAUGHT`, `UNCAUGHT` and `COMPILATION FAILURE` markers, not repeated summaries. They are log evidence, not a reliable machine protocol; retain and review the raw log, particularly multiline patches or unusual project output. The timeout marker is counted separately. Upstream treats timeouts as test failure/caught outcomes, so a timeout must never become a confirmed kill. `confirmed_killed` remains `null` even without observed timeouts: a caught mutant can reflect a build/runtime error or another failing process, not necessarily a valid failing assertion. Review survivors, equivalent mutants, compile failures, error paths and coverage before making any test-quality statement. No mutation percentage is converted into a security assurance claim.
