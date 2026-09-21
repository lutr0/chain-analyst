#!/usr/bin/env bash
# Evidence collection only: project-controlled builds/tests must be trusted or isolated.
set +x
set -euo pipefail
umask 077
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../helpers.sh"
fail() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
(( $# >= 2 )) || fail 'Usage: audit-contracts.sh <project-dir> <new-artifact-dir> [--mutation <source-path>] [--slither]'
require_commands jq realpath mkdir cp
PROJECT=$(realpath -e -- "$1") || fail 'Project directory does not exist.'
[[ -d "$PROJECT" && -f "$PROJECT/foundry.toml" ]] || fail 'Expected a Foundry project directory containing foundry.toml.'
ARTIFACTS=$(realpath -m -- "$2")
[[ ! -e "$ARTIFACTS" && ! -L "$ARTIFACTS" ]] || fail 'Artifact directory must be new; existing evidence will not be overwritten.'
[[ "$ARTIFACTS" != "$PROJECT" && "$ARTIFACTS" != "$PROJECT/"* && "$PROJECT" != / ]] || fail 'Artifact directory must be outside the project.'
shift 2
SOURCE=''
SLITHER=false
while (( $# )); do
  case "$1" in
    --mutation) (( $# >= 2 )) && [[ -n "$2" && -z "$SOURCE" ]] || fail '--mutation requires one source path and cannot be repeated.'; SOURCE=$2; shift 2 ;;
    --slither) [[ "$SLITHER" == false ]] || fail '--slither cannot be repeated.'; SLITHER=true; shift ;;
    *) fail "Unknown argument: $1" ;;
  esac
done
printf '%s\n' 'WARNING: Review untrusted project configuration first. Tests, build hooks, FFI and analyzers execute project-controlled code. Use isolation without production credentials. Forge may write normal local build artifacts. Logs may contain project-emitted secrets; protect and review them before sharing.' >&2
mkdir -p -- "$(dirname "$ARTIFACTS")"
mkdir -- "$ARTIFACTS" || fail 'Could not exclusively create artifact directory.'
: > "$ARTIFACTS/commands.jsonl"
: > "$ARTIFACTS/checks.jsonl"
cd -- "$PROJECT"
RC=0
# Fixed call sites below choose commands; never evaluate configuration or tool output.
record_command() {
  local name=$1 code=$2; shift 2
  jq -cn --arg name "$name" --arg cwd "$PROJECT" --argjson exit_code "$code" --args \
    '{name:$name,cwd:$cwd,argv:$ARGS.positional,exit_code:$exit_code}' -- "$@" >> "$ARTIFACTS/commands.jsonl"
}
run() {
  local name=$1; shift
  RC=0
  "$@" > "$ARTIFACTS/$name.stdout.log" 2> "$ARTIFACTS/$name.stderr.log" || RC=$?
  record_command "$name" "$RC" "$@"
}
check() {
  jq -cn --arg name "$1" --arg status "$2" --arg reason "$3" \
    '{name:$name,status:$status,reason:$reason}' >> "$ARTIFACTS/checks.jsonl"
}

run jq-version jq --version
run bash-version bash --version
if (require_commands git); then
  run git-version git --version
  run git-root git rev-parse --show-toplevel
  if (( RC == 0 )); then
    run git-branch git symbolic-ref --quiet --short HEAD
    BRANCH=$(< "$ARTIFACTS/git-branch.stdout.log")
    [[ -n "$BRANCH" ]] || BRANCH='(detached HEAD or unborn branch)'
    run git-commit git rev-parse --verify HEAD
    COMMIT_RC=$RC
    COMMIT=$(< "$ARTIFACTS/git-commit.stdout.log")
    run git-status git status --porcelain=v1 --untracked-files=all
    GIT_STATUS=$(< "$ARTIFACTS/git-status.stdout.log")
    jq -n --arg branch "$BRANCH" --arg commit "$COMMIT" --arg status "$GIT_STATUS" \
      '{repository:true,branch:$branch,commit:$commit,dirty:($status != ""),porcelain:$status}' > "$ARTIFACTS/source.json"
    if (( RC == 0 && COMMIT_RC == 0 )); then check snapshot recorded 'Git branch, commit and tracked/untracked dirty state captured before gates.'
    else check snapshot blocked 'Git commit or status unavailable (possibly an unborn branch); inspect logs.'; fi
  else
    printf '%s\n' '{"repository":false,"note":"No Git snapshot available; inspect git-root logs."}' > "$ARTIFACTS/source.json"
    check snapshot recorded 'Project is not a Git repository; no commit identity claimed.'
  fi
else
  printf '%s\n' '{"repository":null,"note":"git is unavailable"}' > "$ARTIFACTS/source.json"
  check snapshot blocked 'git is missing from PATH; provide git to record source identity.'
fi

FULL_PASS=false
if (require_commands forge); then
  run forge-version forge --version
  if (( RC != 0 )); then check forge_version blocked 'forge --version failed; inspect logs.'; fi
  # Raw config can contain RPC credentials. Keep it only in memory and persist an allowlist.
  CONFIG_RC=0
  CONFIG=$(forge config --json 2>/dev/null) || CONFIG_RC=$?
  record_command forge-config "$CONFIG_RC" forge config --json
  CONFIG_OK=false
  if (( CONFIG_RC == 0 )) && printf '%s' "$CONFIG" | jq -es 'length == 1 and (.[0]|type) == "object"' >/dev/null 2>&1; then
    printf '%s' "$CONFIG" | jq --arg profile "${FOUNDRY_PROFILE:-default}" '
      {profile:$profile} + with_entries(select(.key as $key |
        ["solc","auto_detect_solc","offline","src","test","script","out","libs","cache_path",
         "optimizer","optimizer_runs","via_ir","evm_version","match_test","no_match_test",
         "match_contract","no_match_contract","match_path","no_match_path","skip"] | index($key)))
      + {fuzz:(.fuzz | if type == "object" then {runs,max_test_rejects,seed,dictionary_weight,include_storage,include_push_bytes} else null end),
         invariant:(.invariant | if type == "object" then {runs,depth,fail_on_revert,call_override,dictionary_weight,include_storage,include_push_bytes,shrink_run_limit,max_assume_rejects} else null end)}
    ' > "$ARTIFACTS/config.json"
    CONFIG_OK=true
    check configuration recorded 'Allowlisted effective forge configuration captured; raw configuration and diagnostics intentionally not persisted.'
  else
    check configuration blocked 'forge config --json failed or returned invalid JSON. Run it privately to diagnose; raw output is suppressed to protect RPC credentials.'
  fi
  unset CONFIG
  # Record only filter variable names, never arbitrary environment values.
  FILTER_ENV=()
  while IFS= read -r KEY; do
    case "$KEY" in
      FOUNDRY_*MATCH*|DAPP_*MATCH*|FOUNDRY_SKIP|DAPP_SKIP)
        [[ -z "${!KEY}" ]] || FILTER_ENV+=("$KEY") ;;
    esac
  done < <(compgen -e)
  jq -n --args '$ARGS.positional' -- "${FILTER_ENV[@]}" > "$ARTIFACTS/filter-environment.json"
  FILTERED=true
  if [[ "$CONFIG_OK" == true ]] && (( ${#FILTER_ENV[@]} == 0 )) && jq -e '
    [.match_test,.no_match_test,.match_contract,.no_match_contract,.match_path,.no_match_path,.skip]
    | all(.[]; . == null or . == "" or . == [])' "$ARTIFACTS/config.json" >/dev/null; then FILTERED=false; fi

  run formatting forge fmt --check
  if (( RC == 0 )); then check formatting passed 'Formatting check completed.'; else check formatting failed 'forge fmt --check failed; inspect logs.'; fi
  run lint forge lint
  if (( RC == 0 )); then check lint review_required 'Lint completed; review warnings in logs (exit zero does not imply no findings).'; else check lint failed 'forge lint failed or is unsupported by installed Forge; inspect logs.'; fi
  if [[ "$FILTERED" == true ]]; then
    check tests blocked 'Cannot establish an unfiltered suite: inspect config.json and filter-environment.json, remove configured/environment filters and rerun into a new directory.'
    check coverage blocked 'Coverage not run because effective configuration is unavailable or test/build filters are present.'
  else
    run tests forge test --force --json
    TEST_RC=$RC
    # Preserve the exact JSON stdout separately from the parsed aggregate.
    cp -- "$ARTIFACTS/tests.stdout.log" "$ARTIFACTS/tests.json"
    if jq -es '
      if length != 1 or (.[0]|type) != "object" then error("expected one test result object") else .[0] end
      | if all(.[]; type == "object" and (.test_results|type) == "object") then . else error("invalid suite") end
      | [to_entries[] | .key as $suite | .value.test_results | to_entries[] |
          {suite:$suite,test:.key,status:.value.status}]
      | if all(.[]; .status == "Success" or .status == "Failure" or .status == "Skipped") then . else error("unrecognized test status") end
      | {total:length,passed:([.[]|select(.status == "Success")]|length),failed:([.[]|select(.status == "Failure")]|length),
         skipped:([.[]|select(.status == "Skipped")]|length),nonpassing:[.[]|select(.status != "Success")]}
    ' "$ARTIFACTS/tests.json" > "$ARTIFACTS/test-counts.json" 2> "$ARTIFACTS/test-counts.stderr.log"; then
      if (( TEST_RC != 0 )); then check tests failed 'Full test process exited nonzero; see exact counts and logs.'
      elif jq -e '.total > 0 and .failed == 0 and .skipped == 0' "$ARTIFACTS/test-counts.json" >/dev/null; then
        FULL_PASS=true; check tests passed 'Unfiltered suite completed with nonzero tests and zero failures or skips.'
      elif jq -e '.failed > 0' "$ARTIFACTS/test-counts.json" >/dev/null; then check tests failed 'Full suite reported failed tests despite a zero process exit.'
      else check tests blocked 'Empty suite or skipped tests cannot satisfy the full test gate.'; fi
    else check tests failed 'Missing/malformed test JSON or unknown test statuses; no passing suite claimed.'; fi
    run coverage forge coverage --report summary --report lcov --report-file "$ARTIFACTS/coverage.lcov"
    if (( RC == 0 )) && [[ -s "$ARTIFACTS/coverage.lcov" ]]; then
      check coverage review_required 'Coverage summary and LCOV captured; review scope and instrumentation limitations separately from full tests.'
    else check coverage failed 'Coverage command failed or produced no LCOV artifact; inspect logs.'; fi
  fi
else
  for GATE in configuration formatting lint tests coverage; do check "$GATE" blocked 'forge is missing from PATH; install/provide a supported Foundry release explicitly, then rerun.'; done
fi

if [[ "$SLITHER" == true ]]; then
  if (require_commands slither); then
    run slither-version slither --version
    run slither slither . --json "$ARTIFACTS/slither.json"
    SLITHER_RC=$RC
    if [[ -f "$ARTIFACTS/slither.json" ]] && jq -e '
      .success == true and .error == null and (.results|type == "object") and
      (.results | if has("detectors") then (.detectors|type == "array") else true end)
      ' "$ARTIFACTS/slither.json" >/dev/null 2>&1; then
      jq '(.results.detectors // []) as $detectors |
        {raw_findings:($detectors|length),deduplicated_findings:($detectors|unique_by(.id // [.check,.description])|length),
        detector_counts:($detectors|group_by(.check)|map({detector:.[0].check,count:length})),manual_triage_required:true}' \
        "$ARTIFACTS/slither.json" > "$ARTIFACTS/slither-counts.json"
      if (( SLITHER_RC == 0 )) || { (( SLITHER_RC == 255 )) && jq -e '.raw_findings > 0' "$ARTIFACTS/slither-counts.json" >/dev/null; }; then
        check slither review_required 'Analyzer completed; detector findings, exclusions and deltas require manual triage, not a security verdict.'
      else check slither failed 'Slither returned an unexpected error exit status despite JSON output; inspect logs.'; fi
    else check slither failed 'Slither tool error or missing/invalid successful detector JSON; do not confuse tool failure with findings.'; fi
  else check slither blocked 'slither is missing from PATH; provide it explicitly to run the requested static analysis.'; fi
else check slither not_requested 'Optional Slither analysis was not requested; not a successful static-analysis gate.'; fi

if [[ -n "$SOURCE" ]]; then
  if [[ "$FULL_PASS" != true ]]; then check mutation blocked 'Mutation requires a passing full suite with nonzero tests and zero skips.'
  elif [[ ! -f "$SCRIPT_DIR/mutate-contracts.sh" ]]; then check mutation blocked 'Mutation helper is unavailable.'
  else
    run mutation bash "$SCRIPT_DIR/mutate-contracts.sh" "$PROJECT" "$ARTIFACTS/mutation" "$SOURCE"
    MUTATION_RC=$RC
    if [[ -f "$ARTIFACTS/mutation/summary.json" ]] && jq -e '.status == "review_required" or .status == "blocked" or .status == "failed"' "$ARTIFACTS/mutation/summary.json" >/dev/null 2>&1; then
      MUTATION_STATUS=$(jq -r '.status' "$ARTIFACTS/mutation/summary.json")
      if [[ "$MUTATION_STATUS" == review_required ]] && (( MUTATION_RC != 0 )); then MUTATION_STATUS=failed; fi
      check mutation "$MUTATION_STATUS" 'See mutation/summary.json; raw campaign results always require manual triage.'
    else check mutation failed 'Mutation helper returned no valid summary; inspect logs.'; fi
  fi
else check mutation not_requested 'Mutation was not requested.'; fi

jq -n --arg project "$PROJECT" --arg artifacts "$ARTIFACTS" \
  --slurpfile checks "$ARTIFACTS/checks.jsonl" --slurpfile commands "$ARTIFACTS/commands.jsonl" \
  '{project:$project,artifacts:$artifacts,evidence_only:true,manual_review_required:true,
    status:(if any($checks[]; .status == "failed") then "failed" elif any($checks[]; .status == "blocked") then "blocked" else "review_required" end),
    checks:$checks,commands:$commands,notice:"Evidence only, never a full audit pass or security certification. Review source, findings, scope and logs manually."}' > "$ARTIFACTS/summary.json"
jq . "$ARTIFACTS/summary.json"
jq -e '.status == "review_required"' "$ARTIFACTS/summary.json" >/dev/null
