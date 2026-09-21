#!/usr/bin/env bash
# Source-write isolation only: trusted project configuration and scripts are required.
set -Eeuo pipefail
umask 077
export LC_ALL=C NO_COLOR=1
command -v jq >/dev/null || { echo 'Missing jq; install it explicitly before running mutation evidence.' >&2; exit 2; }
project='' output='' work='' child='' before='' after=''
status=blocked reason='Mutation setup did not complete.' mutation_exit=null
counts='{"caught":null,"uncaught":null,"compilation_failure":null,"timeouts":null,"outcome_markers":null}'
baseline='null'
checksum() {
    (cd "$project" && find . -type f -name '*.sol' -print0 | sort -z | xargs -0 -r sha256sum --zero | sha256sum) | cut -d ' ' -f 1
}
finish() {
    local rc=$?
    trap - EXIT INT TERM HUP
    if [[ -n "$child" ]]; then
        kill -TERM -- "-$child" 2>/dev/null || true
        wait "$child" 2>/dev/null || true
    fi
    if [[ -n "$before" ]]; then
        after=$(checksum) || after='unavailable'
        if [[ "$before" != "$after" ]]; then
            status=failed reason='Original Solidity checksum changed; inspect concurrent edits or project-controlled code. No restoration was attempted.'
            rc=1
        fi
    fi
    [[ -z "$work" ]] || rm -rf -- "$work"
    local result
    result=$(jq -n --arg status "$status" --arg reason "$reason" --arg project "$project" \
        --arg output "$output" --arg before "$before" --arg after "$after" \
        --argjson baseline "$baseline" --argjson counts "$counts" --argjson exit_code "$mutation_exit" \
        '{status:$status,reason:$reason,project:$project,artifacts:$output,baseline:$baseline,
          mutation_exit_code:$exit_code,raw_mutant_outcomes:$counts,confirmed_killed:null,
          original_solidity_sha256:{before:$before,after:$after},security_certification:false}')
    if [[ -n "$output" ]]; then printf '%s\n' "$result" > "$output/summary.json"; fi
    printf '%s\n' "$result"
    exit "$rc"
}
trap 'finish' EXIT
trap 'status=blocked; reason="Interrupted; campaign is incomplete."; exit 130' INT
trap 'status=blocked; reason="Terminated; campaign is incomplete."; exit 143' TERM HUP
block() { reason=$1; exit 2; }
[[ $# == 3 ]] || block 'Usage: bash scripts/mutate-contracts.sh <project-dir> <new-artifact-dir> <source-path>'
for cmd in realpath find sort xargs sha256sum cut tar mktemp rm mkdir setsid timeout forge slither slither-mutate solc; do
    command -v "$cmd" >/dev/null || block "Missing $cmd. Install tools explicitly; mutation requires Slither 0.11.6, Forge, and a compatible solc on PATH."
done
project=$(realpath -e -- "$1") || block 'Project directory does not exist.'
[[ -d "$project" && -f "$project/foundry.toml" ]] || block 'Expected a self-contained Foundry project with foundry.toml.'
requested=$(realpath -m -- "$2") || block 'Invalid artifact path.'
[[ "$requested" != "$project" && "$requested" != "$project/"* ]] || block 'Artifact directory must be outside the original project.'
[[ ! -e "$requested" && ! -L "$requested" ]] || block 'Artifact path already exists; choose a new directory.'
[[ -d "$(dirname -- "$requested")" ]] || block 'Create the artifact parent directory first.'
mkdir -- "$requested" || block 'Could not create a new artifact directory.'
output=$requested
source_path=$3
[[ -n "$source_path" && "$source_path" != -* && "$source_path" != /* ]] || block 'Source must be a nonempty project-relative Solidity file or directory, not a flag or absolute path.'
[[ "/$source_path/" != *'/../'* ]] || block 'Source traversal (..) is not accepted; use a project-relative path.'
target=$(realpath -e -- "$project/$source_path") || block 'Source does not exist.'
[[ "$target" == "$project" || "$target" == "$project/"* ]] || block 'Source escapes the project.'
if [[ -f "$target" ]]; then
    [[ "$target" == *.sol && -s "$target" ]] || block 'Source file must be a nonempty .sol file.'
elif [[ -d "$target" ]]; then
    [[ -n "$(find "$target" -type f -name '*.sol' -size +0c -print -quit)" ]] || block 'Source directory contains no nonempty Solidity files.'
else
    block 'Source must be a regular file or directory.'
fi
seconds=${MUTATION_TIMEOUT_SECONDS:-300}
[[ "$seconds" =~ ^[1-9][0-9]{0,5}$ ]] || block 'MUTATION_TIMEOUT_SECONDS must be an integer from 1 through 999999.'
slither --version > "$output/slither-version.txt" 2>&1 || block 'Cannot identify installed Slither.'
[[ "$(<"$output/slither-version.txt")" == '0.11.6' ]] || block 'This log adapter requires Slither 0.11.6; explicitly select that version.'
forge --version > "$output/forge-version.txt" 2>&1
solc --version > "$output/solc-version.txt" 2>&1
# Preserve dependencies, including lib and node_modules. Never dereference symlinks.
# The list is shared by validation and copying, so omitted inputs are explicit.
inputs() {
    (cd "$project" && find . \( -name .git -o -name .env -o -name '.env.*' -o -name '*.pem' -o -name '*.key' -o -name .ssh -o -name .aws -o -name .npmrc -o -name .netrc -o -name out -o -name cache -o -name broadcast -o -name coverage -o -name mutation_campaign \) -prune -o "$@")
}
inputs -print0 > "$output/copied-paths.nul"
[[ -z "$(inputs -type l -print -quit)" ]] || block 'Copied inputs contain symlinks. Supply a self-contained checkout with real dependency files (including lib/node_modules), not linked dependencies; no symlinks are followed.'
[[ -z "$(inputs ! -type f ! -type d -print -quit)" ]] || block 'Copied inputs contain special files; use a self-contained regular-file checkout.'
before=$(checksum)
work=$(mktemp -d -- "$(dirname -- "$output")/.chain-analyst-mutation.XXXXXXXX")
mkdir -- "$work/project"
(cd "$project" && tar --null --verbatim-files-from --no-recursion -T "$output/copied-paths.nul" -cf -) | (cd "$work/project" && tar -xf -)
relative=$(realpath --relative-to="$project" -- "$target")
[[ -e "$work/project/$relative" ]] || block 'Selected source was excluded as credentials or generated output; select an ordinary source directory.'
# A separate session lets interruption terminate the tool and its descendants before cleanup.
run_copy() {
    local log=$1; shift
    (cd "$work/project" && exec setsid "$@") > "$log" 2>&1 &
    child=$!
    local rc=0
    wait "$child" || rc=$?
    child=''
    return "$rc"
}
run_copy "$output/baseline.json" timeout --kill-after=10 "$seconds" forge test --force --json || block 'Baseline tests failed or timed out in the disposable copy; inspect baseline.json.'
baseline_result=$(jq -e '
    [.. | objects | select(has("test_results")) | .test_results | to_entries[] | .value.status] as $s |
    if ($s|length)==0 or any($s[]; . != "Success" and . != "Failure" and . != "Skipped") then error("No recognized test results")
    else {passed:([$s[]|select(.=="Success")]|length),failed:([$s[]|select(.=="Failure")]|length),skipped:([$s[]|select(.=="Skipped")]|length)} end
    ' "$output/baseline.json") || block 'Baseline emitted no recognized nonempty Foundry test results.'
baseline=$baseline_result
jq -e '.passed > 0 and .failed == 0 and .skipped == 0' <<< "$baseline" >/dev/null || block 'Mutation requires a passing nonempty baseline without skips.'
# Upstream deletes output-dir if it exists. Only give it this fresh, owned child path.
mutation_exit=0
run_copy "$output/mutation.log" slither-mutate "./$relative" --test-cmd 'forge test --force' \
    --timeout "$seconds" --output-dir "$output/campaign" --verbose --comprehensive || mutation_exit=$?
# Match individual verbose records, never the repeated per-mutator or aggregate summaries.
counts_result=$(jq -Rs '
    gsub("\u001b\\[[0-9;]*m"; "") as $log |
    [ $log | match("INFO:Slither-Mutate:\\[[^]\\r\\n]+\\] Line [0-9]+: [\\s\\S]*? --> (UNCAUGHT|CAUGHT|COMPILATION FAILURE)(?=\\r?\\n|$)"; "g") | .captures[0].string ] as $m |
    {caught:([$m[]|select(.=="CAUGHT")]|length),uncaught:([$m[]|select(.=="UNCAUGHT")]|length),
     compilation_failure:([$m[]|select(.=="COMPILATION FAILURE")]|length),outcome_markers:($m|length),
     timeouts:([$log|match("Tests took too long, consider increasing the timeout";"g")]|length),
     completed:($log|contains("Finished mutation testing assessment of")),
     errors:($log|test("ERROR:Slither-Mutate:|Traceback \\(most recent call last\\)|Cannot find contracts in file|No tests found|No tests to run|Execution interrupted|Ctrl-C received"))}
' "$output/mutation.log") || block 'Could not parse mutation log; retain raw evidence for manual review.'
counts=$counts_result
[[ "$mutation_exit" == 0 ]] || { status=failed; reason='Mutation tool exited nonzero; inspect mutation.log for compiler/import/remapping compatibility or runtime failures.'; exit 1; }
jq -e '.completed and (.outcome_markers > 0) and (.caught + .uncaught > 0) and (.timeouts == 0) and (.errors|not)' <<< "$counts" >/dev/null || block 'Campaign lacks completed, error-free, nonempty executed-mutant evidence. Timeouts, internal errors, unsupported targets and compile-only campaigns are not successful evidence; inspect mutation.log.'
status=review_required
reason='Completed mutation evidence requires manual review. Raw caught outcomes are not confirmed assertion kills; surviving, equivalent, compile-failed and untested mutants need triage. No security score is inferred.'
finish
