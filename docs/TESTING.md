# Testing and measured results (phase 1, local only, no AWS call)

This copy keeps only the A2A communication control results; the model-cost and 30-process scale-run sections are left out.

Commands run from the repo root on 2026-10-10. Python 3.13 via `uv`.

| Layer | Command | Result |
|---|---|---|
| Unit + static | `uv run pytest -m "not live"` | 79 passed |
| Live local A2A (3x3 processes, real models) | `OPENROUTER_API_KEY_FILE=<file> uv run pytest -m live` | 10 passed |
| Everything, after the last format/lint pass | `uv run pytest -q` -> `docs/results/pytest_full.txt` | 89 passed, 0 failed |
| Lint / format | `uv run ruff check --exclude .venv .`; `ruff format --check` | all passed |
| Mutants | `scripts/mutants.sh` -> `docs/results/mutants.txt` | 7 of 7 killed, 0 survivors |

## Must-fail controls
* Disallowed call: `A2AClient.send` raises `A2ADenied` before any socket is opened (`tests/test_client.py`); in the live run the planner->reviewer call not in the rules is refused (`tests/test_live_local.py`).
* Spoofed/missing caller header against a running server is refused with HTTP 200 + JSON-RPC -32003 since the phase 2 fix (`tests/test_models_and_server.py`; the scale run of 2026-10-10 recorded status 403 before that change).
* Mutants (each is a one-line edit of a scratch copy; the named test must fail; output in `docs/results/mutants.txt`): allow policy allows all; spend cap never enforced; server skips check; client skips check; `data_collection` allow; SigV4 service changed; Terraform expands rules backwards.

## Terraform offline checks (`infra/`, no credentials, no plan)
| Check | Result |
|---|---|
| `terraform fmt -check` | clean |
| `terraform validate` | success |
| `tflint` | exit 0 |
| `checkov -d infra` | 61 passed, 0 failed, 8 skipped (each skip inline with a reason) |
| Expansion parity (`scripts/tf_expansion.py` via `terraform console` vs `policy.py`) | equal for team.yaml (`tests/test_infra.py`) |
| IAM scope (`scripts/check_iam_scope.py`) | no wildcard action/resource beyond allow-listed reasons |

Resources by type from the code (`scripts/count_resources.py` -> `docs/results/resource_count.json`), total 67:
agent_runtime 9, resource_policy 9, cloudwatch_log_group 9, iam_role 9, iam_role_policy 15, s3_bucket 1 (+ lifecycle, public access block, SSE, versioning 1 each), s3_object 10, secretsmanager_secret 1.

## NOT tested
Anything on AWS: runtime start, SigV4 acceptance of a real runtime, the resource-policy Deny (PLAN section 2). The uploaded zip's behaviour inside the arm64 runtime is UNTESTED (wheels are aarch64; this host is aarch64 but not the AgentCore image).

## Re-run 2026-10-10
Run on the branch head `d4e6672` (the tree was clean before this section was added), Python 3.13 via `uv`, no AWS call.

| Check | Command | Count |
|---|---|---|
| Full suite incl. 10 live real-model tests | `OPENROUTER_API_KEY_FILE=<file> uv run pytest -q` | 89 passed, 0 failed (114.8 s) |
| Mutants | `bash scripts/mutants.sh` | 7 KILLED, `survivors: 0` |
| Terraform | `terraform fmt -check -recursive`; `terraform validate` on a scratch copy with `init -backend=false`; `tflint --chdir infra` | fmt rc=0; valid; tflint rc=0 |
| checkov | `checkov -d infra --quiet --compact` | 61 passed, 0 failed, 8 skipped |
| Resource count | `uv run python scripts/count_resources.py` | `resources_total` 67 |

Differences from phase 1: none. (The mutant script ran twice, once to count KILLED and once for the survivors line; both gave the same result.)

## Fix round 2026-10-10
Review gaps M1 and M2 (medium) plus the cheap low ones. No AWS call of any kind (`terraform test` uses `mock_provider "aws"`; the tests run with credentials, profile and `ACT_OPENROUTER_SECRET_ID` removed and the instance metadata service off).

| Item | What changed | Evidence |
|---|---|---|
| M1 header | AWS page S14 (PLAN section 2.3a) requires no prefix, so the names stay `X-Act-Caller` / `X-Act-Token` (constants in `src/act_teams/a2a_client.py`). Every runtime has `request_header_configuration { request_header_allowlist = local.request_headers }` (`infra/runtimes.tf`, `infra/locals.tf`) | `tests/test_infra.py::test_terraform_forwards_exactly_the_headers_the_app_reads` (names equal the Python constants, no `x-amz-`/`x-amzn-` prefix); `terraform test` run `every_runtime_forwards_the_headers_the_app_reads` |
| M2 AWS layers | `infra/tests/render.tftest.hcl` (4 runs, one assert per agent and statement, literal expectations for the 3x3 team) via `scripts/tf_test.sh`, wrapped by `tests/test_infra_render.py`. TRAP handled: the mocked `aws_iam_policy_document.json` is `"{}"`; no assertion reads `.json`, they read the statement arguments Terraform evaluated | `scripts/tf_test.sh`: `Success! 4 passed, 0 failed.` |
| No local AWS reach | `scrub_aws_env` (`src/act_teams/local.py`) is applied to every agent subprocess and, through an autouse fixture, to every test (`tests/conftest.py`) | control `test_secret_id_set_locally_fails_without_any_network_call`: `read_key()` raises `NoCredentialsError` with socket creation patched to fail, 0 attempts |
| Low gaps | README: `tflint --init`, spend-cap wording (one cap per ledger: local code default $2 shared per run, Terraform `spend_cap_usd` $1 per runtime instance); PLAN: four phase-2 checks listed | no code change |

| Check | Command | Count |
|---|---|---|
| Full suite incl. live | `OPENROUTER_API_KEY_FILE=<file> uv run pytest -q` (`docs/results/pytest_full.txt`) | 93 passed, 0 failed (was 89: +1 render, +1 header parity, +2 AWS-reach controls) |
| Live only | `uv run pytest -q -m live` | 10 passed |
| Mutants | `bash scripts/mutants.sh` (`docs/results/mutants.txt`) | **16 of 16 killed**, `survivors: 0` (was 7: the old 7 + P1-P5 + H1-H3 + A1) |
| `terraform test` | `scripts/tf_test.sh` | 4 passed, 0 failed |
| Terraform | `fmt -check -recursive`; `init -backend=false` + `validate` (scratch copy); `tflint --init` + `tflint --chdir infra` | rc 0; valid; rc 0 |
| checkov | `checkov -d infra --quiet --compact` | 61 passed, 0 failed, 8 skipped (unchanged) |
| Resource count | `uv run python scripts/count_resources.py` | 67 (unchanged; the test file adds no resource) |
| Lint | `uv run ruff check --exclude .venv .`; `ruff format` | pass |

Reviewer plants, each applied as a one-line `sed` to a scratch copy by `scripts/mutants.sh` and required to make `terraform test` report "Failure!" (the script rejects a kill that is only an init or import error):
P1 Deny cut to `GetAgentCard`; P2 Deny condition inverted; P3 Allow principal `*`; P4 invoke policy lists every agent; P5 `bedrock:InvokeModel` on the base role: **5 of 5 killed**. Also H1 block removed, H2 wrong allowlist name, H3 app renames its header (killed by the parity test), A1 metadata service enabled (killed by the AWS-reach control).

Differences from before: the test count rose from 89 to 93 and the mutant count from 7 to 16, for the reasons above. Nothing else differs. Note: `terraform init` downloads the AWS provider from the public registry (not an AWS call); `scripts/tf_test.sh` needs that once per scratch copy (about 13 s per run on this host).
Not covered: that the real provider turns these arguments into the JSON AWS expects, and the four phase-2 checks in PLAN (deployed behaviour).

## Fix round 2 2026-10-10 (verifier gaps)
| Gap | Fix | Evidence |
|---|---|---|
| medium: the base-role test never checked `resources` (a widened S3 resource passed) | `infra/tests/render.tftest.hcl` now overrides the bucket and secret ARNs and asserts, per agent, the exact resource set of each of the 4 base statements (own logs, own peer map + code zip, OpenRouter secret, own workload identity) | new plants P6 (S3 resources widened to `bucket/*`, the verifier's own plant), P7 (log-group resource widened), P8 (workload-identity resource widened): each makes `terraform test` report "Failure!" |
| low: H2 and A1 had an empty must-contain text | H2 now requires "Failure! ", A1 requires "NoCredentialsError" | `scripts/mutants.sh` |
| low: the verifier host could not run pytest (no boto3, no `.venv`) | not a code change; the suite needs `uv sync` first (README), and `scripts/tf_test.sh` needs only terraform | counts below are from this host |
| low: A2A header forwarding untested | stays a phase-2 check (PLAN 2.3a and the phase-2 list); the M1 fix rests on AWS documentation only | no change |

| Check | Command | Count |
|---|---|---|
| Full suite incl. live | `OPENROUTER_API_KEY_FILE=<file> uv run pytest -q` | 93 passed, 0 failed (unchanged) |
| Mutants | `bash scripts/mutants.sh` | **19 of 19 killed**, 0 survivors (was 16: +P6, P7, P8) |
| `terraform test` | `scripts/tf_test.sh` | 4 passed, 0 failed (the base-role run now holds 27 asserts, was 18) |
| fmt, validate, tflint, checkov, resources | as in the fix round above | rc 0; valid; rc 0; 61 passed / 0 failed / 8 skipped; 67 |

No AWS call was made.

## Phase 2 results (2026-10-10, AWS run on main 3791a4f0, deployed twice to AgentCore us-east-1, 3 test runs; reported by the operator, not re-run here)
| Finding | Detail | Action |
|---|---|---|
| App refusal never reached the caller | When the container answers non-2xx, AgentCore replaces the answer with HTTP 424 and `{"error":{"code":-32055,"message":"Runtime client error - Please check your CloudWatch logs..."}}`. The old HTTP 403 + -32003 from `allow_check` (`src/act_teams/server.py`) came back as 424/-32055 in 3 of 3 runs for a spoofed caller and for a missing caller header; CloudWatch showed the session opened and the agent never ran, so the refusal itself worked | FIXED in this change: both refusals answer HTTP 200 with the same JSON-RPC error (`REFUSAL_STATUS`), refusal logic unchanged |
| T4: the resource-policy Deny does not apply to the account root user | CONFIRMED by operator run 3 (2026-10-10 05:37-05:50Z, us-east-1; not re-run here). A probe IAM role whose identity policy allows invoke on worker-1 only: worker-1 returned 200 before the resource policies were applied and 403 AccessDeniedException 80 s and 3.4 min after; control probe -> planner-1 (no IAM allow) 403. The account root user -> worker-1 returned 200 all three times (it reached the container and was refused only by the app in runs 1-2). AWS also rejects a runtime policy statement that names more than the runtime ARN ("Policy statement block must contain exactly one resource ARN that matches the provided resource ARN") | AWS layer 2 protects against IAM principals, **not** against the root user. Never use root as a caller outside tests. The run token (next row) closes the gap for a caller that claims a team name |
| Run token was off in every AWS deployment | `server.py` checks `X-Act-Token` only if a token is set, and nothing set `ACT_RUN_TOKEN` on AWS: root sent `X-Act-Caller: planner-1` with no token and worker-1 answered 200, so the app layer trusted the claimed caller (only AWS layers 1 and 2 bind a caller to an IAM identity) | FIXED in this change (below). Untested on AWS |
| T5 IAM simulator | 72 ordered pairs matched `team.yaml` exactly: 19 allowed, 53 denied | none |
| T1 | planner-1 -> worker-1 (task 396) passed 3 of 3 | none |

Local verification of the fix (this change): see "Phase 2 fix" below.

## Phase 2 fix (2026-10-10, local only, no AWS call)
| Check | Command | Result |
|---|---|---|
| Full suite incl. 10 live | `OPENROUTER_API_KEY_FILE=<file> uv run pytest -q` (`docs/results/pytest_full.txt`) | 94 passed, 0 failed (was 93: +1 test that a 200 + JSON-RPC error body raises `A2AError`) |
| Refusal tests | disallowed caller (6 cases), missing caller, wrong/missing run token, live spoof and missing-header cases | each asserts HTTP 200 and error code -32003; the allowed-caller case reaches the A2A handler (code other than -32003) |
| Mutants | `bash scripts/mutants.sh` (`docs/results/mutants.txt`) | 20 of 20 killed, 0 survivors (was 19: +R1 `REFUSAL_STATUS` back to 403, killed by `assert (403 == 200)`) |
| Lint | `uv run ruff check --exclude .venv .` | pass |

Not verified here: that a deployed runtime now passes the -32003 body through (a 2xx answer is the documented condition per the phase 2 report; the operator re-tests on AWS).

## Fix round 2 2026-10-10 (verifier gaps on 12d8eb3)
| Gap | Handling |
|---|---|
| medium: suite and mutants not re-run by the verifier (`uv run --offline` could not download anyio) | Not a defect in the repo: `uv sync` needs network once. Reproduce on a host with network: `uv sync && uv run pytest -q -m "not live"` (84 tests, no key needed) and `bash scripts/mutants.sh` (20 mutants; R1 sets `REFUSAL_STATUS = 403` and must fail `tests/test_models_and_server.py` with `403 == 200`, see `docs/results/mutants.txt`). The 10 live tests need `OPENROUTER_API_KEY_FILE` (a key file) and cost about $0.001; without a key they are skipped, so the key-free figure is 84 passed + 10 deselected |
| medium: 200 + -32003 passing through AgentCore is not confirmed | Still OPEN. Only the operator can confirm it on a deployed runtime; no AWS call is made from this branch. The local tests prove only what the container sends (status 200, code -32003), not what AgentCore forwards |
| low: summary said "nothing is committed" | The harness committed the tree as 12d8eb3 after my reply; I ran no `git commit` or `git push` |
| low: two stale 403 statements | Reworded in `infra/locals.tf` (comment only) and `docs/PLAN.md` line 50; `docs/PLAN.md` line 173 refers to an AWS-side 403 and stays |
| low: regenerated result files | `docs/results/*.txt` are outputs of the commands above, kept as the record; the live part is reproducible only with a key |

## Fix round 3 2026-10-10 (verifier gaps on 1cef734)
| Gap | Handling |
|---|---|
| low: `docs/PLAN.md:42` "Default" column still said 403 | Now `JSON-RPC -32003 in HTTP 200`. Every remaining "403" in README, docs, infra and src was listed with `grep -n 403` and is intentional: the history of the phase 2 finding, the AWS-side refusal at PLAN line 173, and the "answered 403 before" notes |
| medium: suite and mutants not re-run by the verifier (no network for `uv`) | Unchanged environment limit, not a repo defect. This round changes one line in `docs/PLAN.md` and this section only; no code, test or infra file, so the figures on 1cef734 stand (84 passed key-free + 10 live = 94; 20 of 20 mutants). Reproduce with network: `uv sync && uv run pytest -q -m "not live"` and `bash scripts/mutants.sh` |
| medium: AWS pass-through of 200 + -32003 unconfirmed | OPEN, unchanged. Needs a deployed runtime call by the operator; no AWS call is made from this branch |

## Run token wired for AWS (2026-10-10, local and offline only, no AWS call)
What changed: Terraform generates one token per deployment (`random_password.run_token`, `infra/storage.tf`) and stores it in the secret `act-teams/run-token`; each base role may read only that secret (statement `ReadRunToken`, `infra/iam.tf`); each runtime gets `ACT_RUN_TOKEN_SECRET_ID` (the name) and `ACT_REQUIRE_RUN_TOKEN=true` (`infra/runtimes.tf`). At start `resolve_run_token()` (`src/act_teams/server.py`) reads the secret and passes the value in memory to `create_app(run_token=...)` and `A2AClient(run_token=...)`, which check and send `X-Act-Token` (already in the header allowlist). `main()` does not copy it into `os.environ`, so processes the agent spawns do not inherit it (locally `LocalTeam` still uses the `ACT_RUN_TOKEN` environment variable). With the requirement on, a container that cannot read the token exits at start instead of running with the check off.
Limits, stated plainly:
* The token is shared by all agents: it proves membership of the team, not which agent calls. A compromised agent holds it. Identity is bound only by AWS layers 1 and 2 (IAM principal).
* The value is in Terraform state (local state in the shared area, never committed) and in the secret; it is not in any runtime environment variable (asserted by `terraform test`). Anything that can read the secret (the base roles, the deployer, root) can call.
* Callers outside the team (the operator's test script) must read the secret (`output run_token_secret_name`) and send the value as `X-Act-Token`.
* UNTESTED on AWS: that the Secrets Manager read works under the permissions boundary `act-teams-boundary` (the secret name matches the existing `act-teams/*` pattern), that AgentCore forwards `X-Act-Token` (it is in the allowlist), and that root without the token is now refused. Phase-2 checks.

| Check | Command | Count |
|---|---|---|
| Token tests (new) | `uv run pytest -q tests/test_run_token.py` | 9 passed: secret read, empty secret refused, requirement fails closed, right caller without token refused (200 + -32003), with token passes, client sends the header only when set |
| Full suite incl. 10 live | `OPENROUTER_API_KEY_FILE=<file> uv run pytest -q` (`docs/results/pytest_full.txt`) | 103 passed, 0 failed (was 94: +9 token tests) |
| Mutants | `bash scripts/mutants.sh` (`docs/results/mutants.txt`) | 26 of 26 killed, 0 survivors (was 20: +T1 server skips token check, T2 requirement ignored, T3 client omits header, T4 Terraform stops requiring, T5 token in env, T6 secret right widened) |
| `terraform test` | `scripts/tf_test.sh` | 5 passed, 0 failed (new run: runtime requires the token, names the secret, never carries the value; secret holds the generated token; base role: `ReadRunToken` limited to the one secret) |
| Terraform | `fmt -check -recursive`; `init -backend=false` + `validate`; `tflint`; `checkov -d infra` | rc 0; valid; rc 0; 61 passed, 0 failed, 10 skipped (was 8: two inline skips for the new secret, each with a reason) |
| Resources | `scripts/count_resources.py` | 70 (was 67: + random_password, secretsmanager_secret, secretsmanager_secret_version); the `random` provider (~> 3.6) is new in `infra/.terraform.lock.hcl` |

## Fix round 2026-10-10 on 28ccbca (run token)
| Gap | Fix | Evidence |
|---|---|---|
| medium: runtimes did not depend on the secret VERSION (a container could start before the token value existed) | `depends_on = [aws_iam_role_policy.base, aws_secretsmanager_secret_version.run_token]` in `infra/runtimes.tf` | `tests/test_infra_static.py::test_runtimes_wait_for_the_run_token_value` (+ a planted-text control); mutant T7 removes the dependency and is killed by that test |
| low: T4-T6 (and P1-P8, H1) accepted any "Failure! " | `scripts/mutants.sh` now requires the name of the intended `terraform test` run to print `... fail` (e.g. T4 and T5: `run_token_is_required_and_never_in_the_environment"... fail`, T6 and P5-P8: `base_role_has_no_model_or_wildcard_rights"... fail`) | all of them re-run, all killed |
| low: `main()` copied the token into `os.environ` (child processes inherit it) | the token is held in memory and passed to `create_app(run_token=...)` / `A2AClient(run_token=...)` | `test_main_keeps_the_secret_token_out_of_the_environment` (asserts the env has no `ACT_RUN_TOKEN` and the app still enforces the token), `test_a_token_passed_in_works_with_nothing_in_the_environment`, `test_client_sends_a_token_passed_in_without_the_environment`; mutants T8 (main copies it to the env) and T9 (client ignores the passed token) are killed |
| low: AWS-side claims untried; the operator's entry-call script must now send the token | UNCHANGED and stated: the script reads the secret named by the output `run_token_secret_name` and sends its value as `X-Act-Token`, otherwise every entry call returns -32003. Untested on AWS: Secrets Manager read under `act-teams-boundary`, AgentCore forwarding `X-Act-Token`, root without the token refused | phase-2 checks |

| Check | Result |
|---|---|
| Full suite incl. 10 live (`docs/results/pytest_full.txt`) | 108 passed, 0 failed (was 103: +5). The live part ran before a comment-only move in `server.py`; after it the 98 non-live tests were re-run: 98 passed |
| Mutants (`docs/results/mutants.txt`) | 29 of 29 killed, 0 survivors (was 26: +T7, T8, T9) |
| `terraform test` | 5 passed, 0 failed |
| fmt, validate, tflint | rc 0; valid; rc 0 |
| checkov | 61 passed, 0 failed, 10 skipped |
| Resources | 70 |
| ruff | pass |
