#!/usr/bin/env bash
# Must-fail proof: break one guard at a time in a scratch copy and show that the tests fail (assertion failures, not import errors).
# A 5th argument to run() is a text that must appear in the full failing output (proves the tests failed for the intended reason: a
# `terraform test` assertion, not an init or import error).
# Usage: scripts/mutants.sh [out.txt]
set -uo pipefail
cd "$(dirname "$0")/.."; REPO=$PWD
OUT=${1:-docs/results/mutants.txt}; : > "$OUT"
TMP=$(mktemp -d "${TMPDIR:-/tmp}/mut.XXXXXX"); trap 'rm -rf "$TMP"' EXIT
bad=0
run() {  # run NAME FILE SED_EXPR TESTS [MUST_CONTAIN]
  local name=$1 file=$2 expr=$3 tests=$4 must=${5:-}
  rm -rf "$TMP/w"; mkdir "$TMP/w"; cp -r src tests infra scripts team.yaml pyproject.toml "$TMP/w/"; rm -rf "$TMP/w/infra/.terraform"
  sed -i "$expr" "$TMP/w/$file"
  { echo "=== mutant: $name"; echo "--- diff of $file"; diff <(cat "$file") "$TMP/w/$file" || true; } >> "$OUT"
  if cmp -s "$file" "$TMP/w/$file"; then echo "SED DID NOT CHANGE THE FILE: $name" | tee -a "$OUT"; bad=1; return; fi
  local full res; full=$(cd "$TMP/w" && PYTHONDONTWRITEBYTECODE=1 PYTHONPATH="$TMP/w/src" "$REPO/.venv/bin/python" -m pytest -q -x -p no:cacheprovider $tests 2>&1)
  res=$(echo "$full" | tail -4 | cut -c1-400)
  echo "$res" >> "$OUT"
  if echo "$res" | grep -q "failed" && ! echo "$res" | grep -qE "error|Error collecting" && { [ -z "$must" ] || echo "$full" | grep -qF "$must"; }; then echo "KILLED  $name" | tee -a "$OUT"; else echo "SURVIVED $name" | tee -a "$OUT"; bad=1; fi
}
run "allow policy allows everything"        src/act_teams/policy.py   's/return (caller, callee) in self.pairs/return True/'            "tests/test_policy.py"
run "spend cap never enforced"              src/act_teams/spend.py    's/if spent >= self.cap:/if False:/'                              "tests/test_spend.py"
run "server middleware skips the allow check" src/act_teams/server.py 's/if not policy.allows(caller, name):/if False:/'              "tests/test_models_and_server.py"
run "client skips the allow check"          src/act_teams/a2a_client.py 's/self.policy.check(self.caller, callee)  # raises.*/pass/'  "tests/test_client.py"
run "data_collection deny dropped"          src/act_teams/models.py   's/{"data_collection": "deny"}/{"data_collection": "allow"}/'     "tests/test_models_and_server.py"
run "SigV4 signs a different service"       src/act_teams/a2a_client.py 's/^SERVICE = "bedrock-agentcore"/SERVICE = "execute-api"/'  "tests/test_client.py"
run "terraform expands the rules backwards" infra/locals.tf           's/p.to if p.from == a/p.from if p.to == a/'                      "tests/test_infra.py"
RT=tests/test_infra_render.py; TA="Failure! "
run "P1 resource-policy Deny cut to GetAgentCard only" infra/resource_policy.tf 's/actions   = local.invoke_actions/actions   = ["bedrock-agentcore:GetAgentCard"]/' "$RT" 'resource_policy_allows_listed_callers_and_denies_everyone_else"... fail'
run "P2 resource-policy Deny condition inverted"      infra/resource_policy.tf 's/test     = "StringNotEquals"/test     = "StringEquals"/' "$RT" 'resource_policy_allows_listed_callers_and_denies_everyone_else"... fail'
run "P3 resource-policy Allow principal widened to *" infra/resource_policy.tf 's/identifiers = local.allowed_principals\[each.key\]/identifiers = ["*"]/' "$RT" 'resource_policy_allows_listed_callers_and_denies_everyone_else"... fail'
run "P4 invoke policy lists every agent"              infra/iam.tf 's/\[for p in each.value : \[/[for p in keys(local.agents) : [/' "$RT" 'invoke_policy_is_exactly_the_allowed_peers"... fail'
run "P5 base role gains bedrock:InvokeModel"          infra/iam.tf 's/"logs:DescribeLogStreams"\]/"logs:DescribeLogStreams", "bedrock:InvokeModel"]/' "$RT" 'base_role_has_no_model_or_wildcard_rights"... fail'
run "P6 base role S3 resource widened to the whole bucket" infra/iam.tf 's#"${aws_s3_bucket.code.arn}/peers/${each.key}.json", "${aws_s3_bucket.code.arn}/code/agent.zip"#"${aws_s3_bucket.code.arn}/*"#' "$RT" 'base_role_has_no_model_or_wildcard_rights"... fail'
run "P7 base role log-group resource widened"             infra/iam.tf 's#log-group:${local.log_prefix}/#log-group:*/#g' "$RT" 'base_role_has_no_model_or_wildcard_rights"... fail'
run "P8 base role workload-identity resource widened"     infra/iam.tf 's#workload-identity/${local.runtime_name\[each.key\]}-\*"#workload-identity/*"#' "$RT" 'base_role_has_no_model_or_wildcard_rights"... fail'
run "H1 runtime request_header_configuration removed" infra/runtimes.tf '/request_header_configuration {/,/^  }$/d' "$RT" 'every_runtime_forwards_the_headers_the_app_reads"... fail'
run "H2 allowlist names another header"               infra/locals.tf 's/request_headers = \["X-Act-Caller", "X-Act-Token"\]/request_headers = ["X-Wrong", "X-Act-Token"]/' "$RT tests/test_infra.py" "Failure! "
run "H3 app renames its caller header"                src/act_teams/a2a_client.py 's/^CALLER_HEADER = "X-Act-Caller"/CALLER_HEADER = "X-Act-Who"/' "tests/test_infra.py" "request_headers"
run "A1 local run may use the instance metadata service" src/act_teams/local.py 's/AWS_EC2_METADATA_DISABLED="true"/AWS_EC2_METADATA_DISABLED="false"/' "tests/test_models_and_server.py" "NoCredentialsError"
run "R1 refusal answers HTTP 403 again (AgentCore turns that into 424)" src/act_teams/server.py 's/^REFUSAL_STATUS = 200/REFUSAL_STATUS = 403/' "tests/test_models_and_server.py" "403 == 200"
RTK=tests/test_run_token.py
run "T1 server skips the run-token check"             src/act_teams/server.py 's/if token and request.headers.get(TOKEN_HEADER) != token:/if False:/' "$RTK" "test_right_caller_without_the_token"
run "T2 AWS deployment may start without a token"     src/act_teams/server.py 's/if env.get("ACT_REQUIRE_RUN_TOKEN") == "true":/if False:/' "$RTK" "test_aws_deployment_refuses"
run "T3 client does not send the token"               src/act_teams/a2a_client.py 's/^        if run_token:$/        if False:/' "$RTK" "test_client_sends"
run "T4 Terraform stops requiring the token"          infra/runtimes.tf 's/ACT_REQUIRE_RUN_TOKEN    = "true"/ACT_REQUIRE_RUN_TOKEN    = "false"/' "$RT" 'run_token_is_required_and_never_in_the_environment"... fail'
run "T5 Terraform puts the token in the environment"  infra/runtimes.tf 's/^    ACT_SPEND_LEDGER /    ACT_RUN_TOKEN = random_password.run_token.result\n    ACT_SPEND_LEDGER /' "$RT" 'run_token_is_required_and_never_in_the_environment"... fail'
run "T6 run-token secret read right widened"          infra/iam.tf 's/resources = \[aws_secretsmanager_secret.run_token.arn\]/resources = ["arn:aws:secretsmanager:*:*:secret:*"]/' "$RT" 'base_role_has_no_model_or_wildcard_rights"... fail'
run "T7 runtimes stop waiting for the token value"     infra/runtimes.tf 's/depends_on = \[aws_iam_role_policy.base, aws_secretsmanager_secret_version.run_token\]/depends_on = [aws_iam_role_policy.base]/' "tests/test_infra_static.py" "test_runtimes_wait_for_the_run_token_value"
run "T8 main copies the secret token into os.environ"  src/act_teams/server.py 's/^    token = resolve_run_token()$/    token = resolve_run_token(); os.environ["ACT_RUN_TOKEN"] = token or ""/' "$RTK" "test_main_keeps"
run "T9 client ignores a token passed in"              src/act_teams/a2a_client.py 's/run_token = self.run_token or os.environ.get("ACT_RUN_TOKEN")/run_token = os.environ.get("ACT_RUN_TOKEN")/' "$RTK" "test_client_sends_a_token_passed_in"
echo "survivors: $bad" | tee -a "$OUT"
exit $bad
