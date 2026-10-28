# AWS layer 2 (callee side, explicit deny): each runtime allows its listed callers and denies every other principal.
# Callers: the roles of the agents that team.yaml allows to call it, plus the invoker role on entry agents only.

data "aws_iam_role" "invoker" {
  name = var.invoker_role_name
}

locals {
  invoke_actions = [
    "bedrock-agentcore:InvokeAgentRuntime",
    "bedrock-agentcore:InvokeAgentRuntimeForUser",
    "bedrock-agentcore:InvokeAgentRuntimeCommand",
    "bedrock-agentcore:InvokeAgentRuntimeCommandShell",
    "bedrock-agentcore:InvokeAgentRuntimeWithWebSocketStream",
    "bedrock-agentcore:InvokeAgentRuntimeWithWebSocketStreamForUser",
    "bedrock-agentcore:StopRuntimeSession",
    "bedrock-agentcore:GetAgentCard",
  ]

  allowed_principals = {
    for a in keys(local.agents) : a => concat(
      [for c in local.callers[a] : aws_iam_role.agent[c].arn],
      contains(local.entry_agents, a) ? [data.aws_iam_role.invoker.arn] : [],
    )
  }
}

data "aws_iam_policy_document" "runtime" {
  for_each = local.agents

  dynamic "statement" {
    for_each = length(local.allowed_principals[each.key]) > 0 ? [1] : []

    content {
      sid       = "AllowListedCallers"
      effect    = "Allow"
      actions   = ["bedrock-agentcore:InvokeAgentRuntime"]
      resources = [aws_bedrockagentcore_agent_runtime.agent[each.key].agent_runtime_arn]

      principals {
        type        = "AWS"
        identifiers = local.allowed_principals[each.key]
      }
    }
  }

  statement {
    sid       = "DenyEveryoneElse"
    effect    = "Deny"
    actions   = local.invoke_actions
    resources = [aws_bedrockagentcore_agent_runtime.agent[each.key].agent_runtime_arn]

    principals {
      type        = "AWS"
      identifiers = ["*"]
    }

    dynamic "condition" {
      for_each = length(local.allowed_principals[each.key]) > 0 ? [1] : []

      content {
        test     = "StringNotEquals"
        variable = "aws:PrincipalArn"
        values   = local.allowed_principals[each.key]
      }
    }
  }
}

resource "aws_bedrockagentcore_resource_policy" "runtime" {
  for_each     = local.agents
  resource_arn = aws_bedrockagentcore_agent_runtime.agent[each.key].agent_runtime_arn
  policy       = data.aws_iam_policy_document.runtime[each.key].json
}
