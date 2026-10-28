# One AgentCore runtime per agent in team.yaml: A2A protocol, direct code (zip), Python 3.13, public network, SigV4 inbound (no JWT authorizer).

resource "aws_bedrockagentcore_agent_runtime" "agent" {
  for_each           = local.agents
  agent_runtime_name = local.runtime_name[each.key]
  description        = "${local.team.project} ${each.value} agent ${each.key}"
  role_arn           = aws_iam_role.agent[each.key].arn

  agent_runtime_artifact {
    code_configuration {
      entry_point = ["main.py"]
      runtime     = local.team.runtime.python # PYTHON_3_13

      code {
        s3 {
          bucket = aws_s3_bucket.code.id
          prefix = aws_s3_object.code.key
        }
      }
    }
  }

  network_configuration {
    network_mode = "PUBLIC"
  }

  protocol_configuration {
    server_protocol = "A2A"
  }

  request_header_configuration {
    request_header_allowlist = local.request_headers
  }

  lifecycle_configuration {
    idle_runtime_session_timeout = local.team.runtime.idle_timeout_s
    max_lifetime                 = local.team.runtime.max_lifetime_s
  }

  environment_variables = {
    ACT_AGENT_NAME           = each.key
    ACT_AUTH                 = local.auth_mode
    ACT_PEERS_SOURCE         = "s3://${aws_s3_bucket.code.id}/peers/${each.key}.json"
    ACT_OPENROUTER_SECRET_ID = aws_secretsmanager_secret.openrouter.name
    ACT_RUN_TOKEN_SECRET_ID  = aws_secretsmanager_secret.run_token.name # the name only; the value is read at start (never in the environment)
    ACT_REQUIRE_RUN_TOKEN    = "true"                                   # the container exits at start if the token cannot be read
    ACT_SPEND_LEDGER         = "/tmp/act_spend.jsonl"
    ACT_SPEND_CAP_USD        = tostring(var.spend_cap_usd)
    AWS_REGION               = local.region
  }

  # the token must exist before a container starts (it reads the secret value at start and exits if it cannot)
  depends_on = [aws_iam_role_policy.base, aws_secretsmanager_secret_version.run_token]
}

# Created before first use so that destroy removes it; the service would otherwise create the group and leave it behind (HYPOTHESIS, verify in phase 2).
resource "aws_cloudwatch_log_group" "runtime" {
  #checkov:skip=CKV_AWS_158:no CMK, it would outlive destroy
  #checkov:skip=CKV_AWS_338:test deployment, 7 days is enough and cheaper than 365
  for_each          = local.agents
  name              = "${local.log_prefix}/${aws_bedrockagentcore_agent_runtime.agent[each.key].agent_runtime_id}-DEFAULT"
  retention_in_days = var.log_retention_days
}
