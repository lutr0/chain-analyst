#!/usr/bin/env bash
# Real-tool integration: provide Forge, Slither (including slither-mutate), and solc on PATH.
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
for tool in forge slither slither-mutate solc jq git sha256sum find sort xargs tar timeout setsid realpath; do
    command -v "$tool" >/dev/null || { printf 'SKIP: audit-smoke requires %s on PATH\n' "$tool" >&2; exit 77; }
done
WORK=$(mktemp -d /tmp/chain-analyst-audit-smoke.XXXXXXXX)
trap 'rc=$?; if (( rc == 0 )); then rm -rf -- "$WORK"; else printf "Smoke evidence retained: %s\n" "$WORK" >&2; fi' EXIT
PROJECT="$WORK/project with spaces"
ARTIFACTS="$WORK/audit evidence"
mkdir -p "$PROJECT/src" "$PROJECT/test"
cat > "$PROJECT/foundry.toml" <<TOML
[profile.default]
solc = $(jq -cn --arg compiler "$(command -v solc)" '$compiler')
auto_detect_solc = false
offline = true
evm_version = 'paris'
TOML
cat > "$PROJECT/src/Counter.sol" <<'SOL'
// SPDX-License-Identifier: MIT
pragma solidity >=0.8.19 <0.9.0;

contract Counter {
    uint256 public number;

    function setNumber(uint256 next) public {
        number = next;
    }

    function increment() public {
        number++;
    }
}
SOL
cat > "$PROJECT/test/Counter.t.sol" <<'SOL'
// SPDX-License-Identifier: MIT
pragma solidity >=0.8.19 <0.9.0;

import {Counter} from "../src/Counter.sol";

contract CounterTest {
    Counter internal counter;

    function setUp() public {
        counter = new Counter();
    }

    function testInitial() public view {
        require(counter.number() == 0);
    }

    function testIncrement() public {
        counter.increment();
        require(counter.number() == 1);
    }

    function testSet() public {
        counter.setNumber(42);
        require(counter.number() == 42);
    }
}
SOL
originals=$(sha256sum "$PROJECT/src/Counter.sol" "$PROJECT/test/Counter.t.sol" "$PROJECT/foundry.toml")
bash "$ROOT/scripts/audit-contracts.sh" "$PROJECT" "$ARTIFACTS" --slither --mutation src/Counter.sol > "$WORK/run.log" 2>&1
jq -e '.status == "review_required" and
    any(.checks[]; .name == "slither" and .status == "review_required") and
    any(.checks[]; .name == "mutation" and .status == "review_required")' "$ARTIFACTS/summary.json" >/dev/null
jq -e '.passed > 0 and .failed == 0 and .skipped == 0' "$ARTIFACTS/test-counts.json" >/dev/null
jq -e '.status == "review_required" and .baseline.passed > 0 and
    .baseline.failed == 0 and .baseline.skipped == 0 and
    (.raw_mutant_outcomes.caught + .raw_mutant_outcomes.uncaught > 0) and
    .raw_mutant_outcomes.compilation_failure > 0 and
    .original_solidity_sha256.before == .original_solidity_sha256.after' "$ARTIFACTS/mutation/summary.json" >/dev/null
[[ "$originals" == "$(sha256sum "$PROJECT/src/Counter.sol" "$PROJECT/test/Counter.t.sol" "$PROJECT/foundry.toml")" ]]
jq -es --arg project "$PROJECT" --arg artifacts "$ARTIFACTS" '
    all(.[]; .cwd == $project and (.exit_code|type) == "number" and
        (.argv|type) == "array" and all(.argv[]; type == "string")) and
    any(.[]; .name == "jq-version" and .argv == ["jq", "--version"]) and
    any(.[]; .name == "git-root" and .argv == ["git", "rev-parse", "--show-toplevel"]) and
    any(.[]; .name == "tests" and .argv == ["forge", "test", "--force", "--json"]) and
    any(.[]; .name == "slither" and .argv == ["slither", ".", "--json", ($artifacts + "/slither.json")])
    ' "$ARTIFACTS/commands.jsonl" >/dev/null
fingerprint() {
    (cd "$ARTIFACTS" && find . -type f -print0 | sort -z | xargs -0 sha256sum --zero | sha256sum)
}
evidence=$(fingerprint)
if bash "$ROOT/scripts/audit-contracts.sh" "$PROJECT" "$ARTIFACTS" --slither --mutation src/Counter.sol > "$WORK/reuse.log" 2>&1; then
    printf 'FAIL: audit runner accepted an existing evidence directory\n' >&2
    exit 1
fi
[[ "$evidence" == "$(fingerprint)" ]]
jq -e '.raw_findings > 0 and .deduplicated_findings > 0' "$ARTIFACTS/slither-counts.json" >/dev/null
printf '%s\n' '{"detectors_to_exclude":"solc-version"}' > "$PROJECT/slither.config.json"
ZERO="$WORK/zero finding evidence"
bash "$ROOT/scripts/audit-contracts.sh" "$PROJECT" "$ZERO" --slither > "$WORK/zero.log" 2>&1
jq -e '.status == "review_required" and any(.checks[]; .name == "slither" and .status == "review_required")' "$ZERO/summary.json" >/dev/null
jq -e '.raw_findings == 0 and .deduplicated_findings == 0 and .detector_counts == []' "$ZERO/slither-counts.json" >/dev/null
printf 'PASS: real audit/mutation evidence, zero findings, argv preservation, source integrity, and reuse rejection\n'
