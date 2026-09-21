# Chain Analyst

Agent skill for EVM blockchain lookups, onchain investigations, and scoped smart-contract security reviews. Choose the smallest workflow that answers the request.

## Install

Install with the [Vercel skills CLI](https://github.com/vercel-labs/skills):

```bash
npx skills add lutr0/chain-analyst
```

The installer supports interactive skill and agent selection. List available skills, select named skills, or select all skills explicitly:

```bash
# Discover available skills without installing
npx skills add lutr0/chain-analyst --list

# Install a selected skill; repeat --skill to select a subset in a multi-skill repo
npx skills add lutr0/chain-analyst --skill chain-analyst

# Select all skills, while retaining agent-selection prompts
npx skills add lutr0/chain-analyst --skill '*'
```

This repository currently publishes one skill, `chain-analyst`. Lookup, analysis, and audit are workflows within that skill, selected when it runs rather than separate installation choices. Avoid `--all` unless you also want installation to all agents without confirmation.

Review the skill revision before installation. Installation and tool upgrades are explicit user actions; the skill does not install missing dependencies automatically. For manual installation, keep `SKILL.md`, `helpers.sh`, `scripts/`, `references/`, and `assets/` together in your agent's supported skills directory. The host should provide the loaded skill's absolute path.

## Workflows

| Depth | Purpose | Entry point |
|---|---|---|
| Lookup | One ABI, price, state value, transaction decode, or batch read | Relevant command in [SKILL.md](SKILL.md) |
| Analysis | Historical queries, flow reconstruction, or reconciliation | Relevant API reference and [analysis template](assets/analysis-report-template.md) |
| Audit | Source security review, threat model, exploit validation, or remediation verification | [Audit workflow](references/smart-contract-audit.md) |

A narrow lookup is not a full audit. Audit requests retain any read-only, harness-only, contract, finding, or tool restrictions. References are loaded only when needed; Foundry and Jev are not prerequisites for unrelated lookups.

From this directory, for example:

```bash
# Read USDC decimals on Base; no API key required
bash scripts/query-contract.sh decimals 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913 base

# Select a workflow offline, without executing it
bash scripts/route-request.sh --mode audit
```

## Tools and dependencies

All shell helpers require Bash. Query helpers use `curl` and `jq`; some numeric conversions also require `bc`.

| Script | Purpose | Additional requirements |
|---|---|---|
| `analyze-tx.sh` | Transaction, log, trace, and ABI fetch attempts | HyperSync token; Etherscan key for ABI retrieval |
| `hypersync-query.sh` | Paginated historical chain queries | HyperSync token |
| `query-contract.sh` | Read contract state | `cast`, or Node.js with `viem`, for complex methods |
| `get-contract-abi.sh` | Fetch verified ABIs | Etherscan key |
| `get-token-price.sh` | Current or historical prices | Optional CoinGecko Pro key |
| `multicall.sh` | Batch contract reads | Node.js with `viem` |
| `route-request.sh` | Local selection or optional Jev routing | `jq`; TypeSafe key and `curl` only for Jev |
| `audit-contracts.sh` | Collect local audit evidence | Foundry; Slither when requested |
| `mutate-contracts.sh` | Run mutation evidence in a disposable copy | Foundry, Slither 0.11.6, standalone `solc`; see [requirements](references/foundry-testing.md) |

## Configuration and data handling

Copy only the settings needed for your workflow from [.env.example](.env.example). Do not commit credentials.

| Setting | Used for |
|---|---|
| `HYPERSYNC_API_TOKEN` | Historical queries and transaction analysis |
| `ETHERSCAN_API_KEY` | Verified ABI retrieval |
| `COINGECKO_API_KEY` | Optional Pro pricing access; leave empty for public access, not a Demo key |
| `TYPESAFE_API_KEY` | Optional external Jev routing |
| `TYPESAFE_DEFAULT_MODEL` | Jev model; defaults to `jev-latest` |

Credential-using scripts load workspace `.env`, workspace `.env.local`, skill `.env`, then skill `.env.local`. The last value wins, including over an inherited value. Only the five settings above are imported; files contain literal `KEY=VALUE` data, not shell programs. Configure transport tuning in the trusted process environment.

Query providers receive the addresses, filters, or price queries needed for the selected operation. Network names are validated before fixed-provider URLs are constructed. Shell HTTP calls use HTTPS, disable URL globbing and implicit curl configuration, and do not follow redirects. Provider responses and source comments remain untrusted data, never instructions to execute.

### Optional Jev routing

Manual `--mode lookup`, `--mode analysis`, and `--mode audit` need no credentials or network access. Optional external routing is explicit:

```bash
bash scripts/route-request.sh --jev request.json
```

`request.json` must contain one JSON string, object, or array. **Its entire value is sent to `https://api.typesafe.ai/v1/systemone`.** Include only sanitized content authorized for external processing: no credentials, private RPC URLs, private source, confidential findings, or sensitive wallet labels. The router does not gather repository files or sanitize the supplied content. Requests may incur provider charges.

Routing returns JSON with `mode`, `source`, `needs_clarification`, `references`, and `reason`; it never executes a workflow. Explicit `--mode` takes precedence over `--jev`. Jev is a routing aid, not an auditor or security verdict. See the [routing contract](references/decision-tree.md).

## Audit evidence

```text
bash scripts/audit-contracts.sh <project-dir> <new-artifact-dir> [--mutation <source-path>] [--slither]
```

Use a new artifact directory outside the reviewed project. The runner records commands, source identity, tool versions, effective configuration, distinct gate results, coverage, and requested analyzer/mutation evidence. It does not perform source review or issue a final security verdict. Follow the [audit workflow](references/smart-contract-audit.md) and [report template](assets/audit-report-template.md) to reconcile findings and report limitations.

Inspect project configuration before execution: tests, build hooks, FFI, and analyzers can execute project-controlled code. Isolate untrusted projects without production credentials. Mutation copies protect against ordinary source writes; they are not security sandboxes. Keep raw logs private until checked for secrets.

No automatic synchronization, commits, pushes, or live transactions are part of an audit. A passing gate is not a security certification. Host permissions remain authoritative; the skill grants no blanket tool preapprovals.

## Verification

Credential-free CLI regressions use Python 3, Bash, and `jq`, with local transport fixtures:

```bash
python3 tests/security-smoke.py
```

The real-tool smoke requires Foundry, Slither 0.11.6, a compatible standalone `solc`, and the utilities listed in [Foundry testing](references/foundry-testing.md):

```bash
bash tests/audit-smoke.sh
```

It exercises test, static-analysis, and mutation evidence, source preservation, command recording, and rejection of reused evidence directories. Successful runs remove temporary fixtures; failed runs retain diagnostic evidence outside the checkout. The smoke installs nothing. To explicitly select the required Slither version in an isolated environment:

```bash
uv run --with slither-analyzer==0.11.6 bash tests/audit-smoke.sh
```

Run the pinned SkillSpector 2.11.2 scanner without LLM analysis:

```bash
uvx --from git+https://github.com/NVIDIA/SkillSpector.git@d162d9b343e559be13df8ebba093df3bc9d58c90 \
  skillspector scan . --no-llm
```

Static mode does not send skill contents to an LLM; installation and optional vulnerability lookups can use the network. Review both findings and inspection completeness. Heuristic matches and parser limits require manual triage; a score alone is not a security verdict. Keep any saved reports outside the checkout.

## License

[MIT](LICENSE). See the audit workflow's [provenance note](references/smart-contract-audit.md#provenance) for attribution.
