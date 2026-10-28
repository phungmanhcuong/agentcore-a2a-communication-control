# One execution role per agent, under /act-teams/ with the permissions boundary. No Bedrock model invocation: models come from OpenRouter.

data "aws_iam_policy_document" "trust" {
  statement {
    sid     = "AgentCoreAssumes"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["bedrock-agentcore.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [local.account_id]
    }

    condition {
      test     = "ArnLike"
      variable = "aws:SourceArn"
      values   = ["${local.ac_arn_base}:*"]
    }
  }
}

resource "aws_iam_role" "agent" {
  for_each             = local.agents
  name                 = "${var.name_prefix}-${each.key}"
  path                 = "/act-teams/"
  permissions_boundary = local.boundary_arn
  assume_role_policy   = data.aws_iam_policy_document.trust.json
}

# Base rights: own log groups, own peer map, the code zip, the OpenRouter secret, the run-token secret, own workload identity. Nothing else.
data "aws_iam_policy_document" "base" {
  for_each = local.agents

  statement {
    sid       = "OwnLogs"
    actions   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents", "logs:DescribeLogStreams"]
    resources = ["arn:aws:logs:${local.region}:${local.account_id}:log-group:${local.log_prefix}/${local.runtime_name[each.key]}-*", "arn:aws:logs:${local.region}:${local.account_id}:log-group:${local.log_prefix}/${local.runtime_name[each.key]}-*:*"]
  }

  statement {
    sid       = "OwnPeerMapAndCode"
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.code.arn}/peers/${each.key}.json", "${aws_s3_bucket.code.arn}/code/agent.zip"]
  }

  statement {
    sid       = "ReadOpenRouterKey"
    actions   = ["secretsmanager:GetSecretValue"]
    resources = [aws_secretsmanager_secret.openrouter.arn]
  }

  statement {
    sid       = "ReadRunToken"
    actions   = ["secretsmanager:GetSecretValue"]
    resources = [aws_secretsmanager_secret.run_token.arn]
  }

  statement {
    sid       = "OwnWorkloadIdentityToken"
    actions   = ["bedrock-agentcore:GetWorkloadAccessToken", "bedrock-agentcore:GetWorkloadAccessTokenForJWT", "bedrock-agentcore:GetWorkloadAccessTokenForUserId"]
    resources = ["${local.ac_arn_base}:workload-identity-directory/default", "${local.ac_arn_base}:workload-identity-directory/default/workload-identity/${local.runtime_name[each.key]}-*"]
  }
}

resource "aws_iam_role_policy" "base" {
  for_each = local.agents
  name     = "base"
  role     = aws_iam_role.agent[each.key].id
  policy   = data.aws_iam_policy_document.base[each.key].json
}

# AWS layer 1 (caller side, deny by default): an agent may invoke exactly the runtimes of its allowed peers. An agent with no allowed peer gets
# no policy at all. Separate resource from the role so the runtime (which needs the role) and this policy (which needs the peers' runtimes) do not cycle.
data "aws_iam_policy_document" "invoke" {
  for_each = { for a, p in local.peers : a => p if length(p) > 0 }

  statement {
    sid     = "InvokeAllowedPeersOnly"
    actions = ["bedrock-agentcore:InvokeAgentRuntime"]
    # the runtime and its endpoints; the endpoint ARN shape differs between the authorization reference and the resource-policy page
    resources = flatten([for p in each.value : [aws_bedrockagentcore_agent_runtime.agent[p].agent_runtime_arn, "${aws_bedrockagentcore_agent_runtime.agent[p].agent_runtime_arn}/*"]])
  }
}

resource "aws_iam_role_policy" "invoke" {
  for_each = data.aws_iam_policy_document.invoke
  name     = "invoke-allowed-peers"
  role     = aws_iam_role.agent[each.key].id
  policy   = each.value.json
}
