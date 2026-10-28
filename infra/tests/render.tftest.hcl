# Offline render test (no AWS call, no credentials): `mock_provider` replaces every AWS API. Run by scripts/tf_test.sh (and tests/test_infra_render.py).
# TRAP: a mocked data "aws_iam_policy_document" returns an invented `json`, so nothing here asserts on `.json`. The assertions read the arguments
# Terraform itself evaluated (statement blocks, principals, resources, conditions) and the values it renders with jsonencode-free HCL expressions.
# What is NOT proven here: that the real provider turns these arguments into the JSON AWS expects (phase 2, deployed call from planner-1 and reviewer-1).
# Expected values are literals for the 3x3 team.yaml on purpose: they must not be computed with the code under test.

mock_provider "random" {
  mock_resource "random_password" {
    defaults = { result = "mock-run-token" }
  }
}

mock_provider "aws" {
  mock_data "aws_caller_identity" {
    defaults = { account_id = "111122223333" }
  }
  mock_data "aws_iam_role" {
    defaults = { arn = "arn:aws:iam::111122223333:role/act-teams-deployer" }
  }
  mock_data "aws_iam_policy_document" {
    defaults = { json = "{}" }
  }
}

override_resource {
  target = aws_s3_bucket.code
  values = { arn = "arn:aws:s3:::act-teams-code-111122223333" }
}
override_resource {
  target = aws_secretsmanager_secret.run_token
  values = { arn = "arn:aws:secretsmanager:us-east-1:111122223333:secret:act-teams/run-token-GhIjKl" }
}
override_resource {
  target = aws_secretsmanager_secret.openrouter
  values = { arn = "arn:aws:secretsmanager:us-east-1:111122223333:secret:act-teams/openrouter-AbCdEf" }
}

override_resource {
  target = aws_iam_role.agent["planner-1"]
  values = { arn = "arn:aws:iam::111122223333:role/act-teams/act-teams-planner-1" }
}
override_resource {
  target = aws_bedrockagentcore_agent_runtime.agent["planner-1"]
  values = { agent_runtime_arn = "arn:aws:bedrock-agentcore:us-east-1:111122223333:runtime/act_teams_planner_1-MOCK", agent_runtime_id = "act_teams_planner_1-MOCK" }
}

override_resource {
  target = aws_iam_role.agent["planner-2"]
  values = { arn = "arn:aws:iam::111122223333:role/act-teams/act-teams-planner-2" }
}
override_resource {
  target = aws_bedrockagentcore_agent_runtime.agent["planner-2"]
  values = { agent_runtime_arn = "arn:aws:bedrock-agentcore:us-east-1:111122223333:runtime/act_teams_planner_2-MOCK", agent_runtime_id = "act_teams_planner_2-MOCK" }
}

override_resource {
  target = aws_iam_role.agent["planner-3"]
  values = { arn = "arn:aws:iam::111122223333:role/act-teams/act-teams-planner-3" }
}
override_resource {
  target = aws_bedrockagentcore_agent_runtime.agent["planner-3"]
  values = { agent_runtime_arn = "arn:aws:bedrock-agentcore:us-east-1:111122223333:runtime/act_teams_planner_3-MOCK", agent_runtime_id = "act_teams_planner_3-MOCK" }
}

override_resource {
  target = aws_iam_role.agent["worker-1"]
  values = { arn = "arn:aws:iam::111122223333:role/act-teams/act-teams-worker-1" }
}
override_resource {
  target = aws_bedrockagentcore_agent_runtime.agent["worker-1"]
  values = { agent_runtime_arn = "arn:aws:bedrock-agentcore:us-east-1:111122223333:runtime/act_teams_worker_1-MOCK", agent_runtime_id = "act_teams_worker_1-MOCK" }
}

override_resource {
  target = aws_iam_role.agent["worker-2"]
  values = { arn = "arn:aws:iam::111122223333:role/act-teams/act-teams-worker-2" }
}
override_resource {
  target = aws_bedrockagentcore_agent_runtime.agent["worker-2"]
  values = { agent_runtime_arn = "arn:aws:bedrock-agentcore:us-east-1:111122223333:runtime/act_teams_worker_2-MOCK", agent_runtime_id = "act_teams_worker_2-MOCK" }
}

override_resource {
  target = aws_iam_role.agent["worker-3"]
  values = { arn = "arn:aws:iam::111122223333:role/act-teams/act-teams-worker-3" }
}
override_resource {
  target = aws_bedrockagentcore_agent_runtime.agent["worker-3"]
  values = { agent_runtime_arn = "arn:aws:bedrock-agentcore:us-east-1:111122223333:runtime/act_teams_worker_3-MOCK", agent_runtime_id = "act_teams_worker_3-MOCK" }
}

override_resource {
  target = aws_iam_role.agent["reviewer-1"]
  values = { arn = "arn:aws:iam::111122223333:role/act-teams/act-teams-reviewer-1" }
}
override_resource {
  target = aws_bedrockagentcore_agent_runtime.agent["reviewer-1"]
  values = { agent_runtime_arn = "arn:aws:bedrock-agentcore:us-east-1:111122223333:runtime/act_teams_reviewer_1-MOCK", agent_runtime_id = "act_teams_reviewer_1-MOCK" }
}

override_resource {
  target = aws_iam_role.agent["reviewer-2"]
  values = { arn = "arn:aws:iam::111122223333:role/act-teams/act-teams-reviewer-2" }
}
override_resource {
  target = aws_bedrockagentcore_agent_runtime.agent["reviewer-2"]
  values = { agent_runtime_arn = "arn:aws:bedrock-agentcore:us-east-1:111122223333:runtime/act_teams_reviewer_2-MOCK", agent_runtime_id = "act_teams_reviewer_2-MOCK" }
}

override_resource {
  target = aws_iam_role.agent["reviewer-3"]
  values = { arn = "arn:aws:iam::111122223333:role/act-teams/act-teams-reviewer-3" }
}
override_resource {
  target = aws_bedrockagentcore_agent_runtime.agent["reviewer-3"]
  values = { agent_runtime_arn = "arn:aws:bedrock-agentcore:us-east-1:111122223333:runtime/act_teams_reviewer_3-MOCK", agent_runtime_id = "act_teams_reviewer_3-MOCK" }
}


# Resource policy on each runtime: Allow the listed callers (invoker role on entry agents), explicit Deny for every other principal.
run "resource_policy_allows_listed_callers_and_denies_everyone_else" {
  command = apply

  assert {
    condition     = length(data.aws_iam_policy_document.runtime["planner-1"].statement) == 2
    error_message = "planner-1: the runtime policy must have exactly one Allow and one Deny statement"
  }

  assert {
    condition     = [for s in data.aws_iam_policy_document.runtime["planner-1"].statement : { effect = s.effect, actions = toset(s.actions), resources = toset(s.resources), types = toset([for p in s.principals : p.type]), principals = toset(flatten([for p in s.principals : p.identifiers])) } if s.sid == "AllowListedCallers"] == [{ effect = "Allow", actions = toset(["bedrock-agentcore:InvokeAgentRuntime"]), resources = toset(["arn:aws:bedrock-agentcore:us-east-1:111122223333:runtime/act_teams_planner_1-MOCK"]), types = toset(["AWS"]), principals = toset(["arn:aws:iam::111122223333:role/act-teams-deployer"]) }]
    error_message = "planner-1: the Allow is not exactly the listed caller roles on this runtime"
  }

  assert {
    condition     = [for s in data.aws_iam_policy_document.runtime["planner-1"].statement : { effect = s.effect, actions = toset(s.actions), resources = toset(s.resources), types = toset([for p in s.principals : p.type]), principals = toset(flatten([for p in s.principals : p.identifiers])), conditions = [for c in s.condition : { test = c.test, variable = c.variable, values = toset(c.values) }] } if s.sid == "DenyEveryoneElse"] == [{ effect = "Deny", actions = toset(["bedrock-agentcore:InvokeAgentRuntime", "bedrock-agentcore:InvokeAgentRuntimeForUser", "bedrock-agentcore:InvokeAgentRuntimeCommand", "bedrock-agentcore:InvokeAgentRuntimeCommandShell", "bedrock-agentcore:InvokeAgentRuntimeWithWebSocketStream", "bedrock-agentcore:InvokeAgentRuntimeWithWebSocketStreamForUser", "bedrock-agentcore:StopRuntimeSession", "bedrock-agentcore:GetAgentCard"]), resources = toset(["arn:aws:bedrock-agentcore:us-east-1:111122223333:runtime/act_teams_planner_1-MOCK"]), types = toset(["AWS"]), principals = toset(["*"]), conditions = [{ test = "StringNotEquals", variable = "aws:PrincipalArn", values = toset(["arn:aws:iam::111122223333:role/act-teams-deployer"]) }] }]
    error_message = "planner-1: the Deny is missing, inverted, narrower than the invoke actions, or exempts other principals"
  }

  assert {
    condition     = aws_bedrockagentcore_resource_policy.runtime["planner-1"].resource_arn == "arn:aws:bedrock-agentcore:us-east-1:111122223333:runtime/act_teams_planner_1-MOCK"
    error_message = "planner-1: the resource policy is not attached to this runtime"
  }

  assert {
    condition     = length(data.aws_iam_policy_document.runtime["planner-2"].statement) == 2
    error_message = "planner-2: the runtime policy must have exactly one Allow and one Deny statement"
  }

  assert {
    condition     = [for s in data.aws_iam_policy_document.runtime["planner-2"].statement : { effect = s.effect, actions = toset(s.actions), resources = toset(s.resources), types = toset([for p in s.principals : p.type]), principals = toset(flatten([for p in s.principals : p.identifiers])) } if s.sid == "AllowListedCallers"] == [{ effect = "Allow", actions = toset(["bedrock-agentcore:InvokeAgentRuntime"]), resources = toset(["arn:aws:bedrock-agentcore:us-east-1:111122223333:runtime/act_teams_planner_2-MOCK"]), types = toset(["AWS"]), principals = toset(["arn:aws:iam::111122223333:role/act-teams-deployer"]) }]
    error_message = "planner-2: the Allow is not exactly the listed caller roles on this runtime"
  }

  assert {
    condition     = [for s in data.aws_iam_policy_document.runtime["planner-2"].statement : { effect = s.effect, actions = toset(s.actions), resources = toset(s.resources), types = toset([for p in s.principals : p.type]), principals = toset(flatten([for p in s.principals : p.identifiers])), conditions = [for c in s.condition : { test = c.test, variable = c.variable, values = toset(c.values) }] } if s.sid == "DenyEveryoneElse"] == [{ effect = "Deny", actions = toset(["bedrock-agentcore:InvokeAgentRuntime", "bedrock-agentcore:InvokeAgentRuntimeForUser", "bedrock-agentcore:InvokeAgentRuntimeCommand", "bedrock-agentcore:InvokeAgentRuntimeCommandShell", "bedrock-agentcore:InvokeAgentRuntimeWithWebSocketStream", "bedrock-agentcore:InvokeAgentRuntimeWithWebSocketStreamForUser", "bedrock-agentcore:StopRuntimeSession", "bedrock-agentcore:GetAgentCard"]), resources = toset(["arn:aws:bedrock-agentcore:us-east-1:111122223333:runtime/act_teams_planner_2-MOCK"]), types = toset(["AWS"]), principals = toset(["*"]), conditions = [{ test = "StringNotEquals", variable = "aws:PrincipalArn", values = toset(["arn:aws:iam::111122223333:role/act-teams-deployer"]) }] }]
    error_message = "planner-2: the Deny is missing, inverted, narrower than the invoke actions, or exempts other principals"
  }

  assert {
    condition     = aws_bedrockagentcore_resource_policy.runtime["planner-2"].resource_arn == "arn:aws:bedrock-agentcore:us-east-1:111122223333:runtime/act_teams_planner_2-MOCK"
    error_message = "planner-2: the resource policy is not attached to this runtime"
  }

  assert {
    condition     = length(data.aws_iam_policy_document.runtime["planner-3"].statement) == 2
    error_message = "planner-3: the runtime policy must have exactly one Allow and one Deny statement"
  }

  assert {
    condition     = [for s in data.aws_iam_policy_document.runtime["planner-3"].statement : { effect = s.effect, actions = toset(s.actions), resources = toset(s.resources), types = toset([for p in s.principals : p.type]), principals = toset(flatten([for p in s.principals : p.identifiers])) } if s.sid == "AllowListedCallers"] == [{ effect = "Allow", actions = toset(["bedrock-agentcore:InvokeAgentRuntime"]), resources = toset(["arn:aws:bedrock-agentcore:us-east-1:111122223333:runtime/act_teams_planner_3-MOCK"]), types = toset(["AWS"]), principals = toset(["arn:aws:iam::111122223333:role/act-teams-deployer"]) }]
    error_message = "planner-3: the Allow is not exactly the listed caller roles on this runtime"
  }

  assert {
    condition     = [for s in data.aws_iam_policy_document.runtime["planner-3"].statement : { effect = s.effect, actions = toset(s.actions), resources = toset(s.resources), types = toset([for p in s.principals : p.type]), principals = toset(flatten([for p in s.principals : p.identifiers])), conditions = [for c in s.condition : { test = c.test, variable = c.variable, values = toset(c.values) }] } if s.sid == "DenyEveryoneElse"] == [{ effect = "Deny", actions = toset(["bedrock-agentcore:InvokeAgentRuntime", "bedrock-agentcore:InvokeAgentRuntimeForUser", "bedrock-agentcore:InvokeAgentRuntimeCommand", "bedrock-agentcore:InvokeAgentRuntimeCommandShell", "bedrock-agentcore:InvokeAgentRuntimeWithWebSocketStream", "bedrock-agentcore:InvokeAgentRuntimeWithWebSocketStreamForUser", "bedrock-agentcore:StopRuntimeSession", "bedrock-agentcore:GetAgentCard"]), resources = toset(["arn:aws:bedrock-agentcore:us-east-1:111122223333:runtime/act_teams_planner_3-MOCK"]), types = toset(["AWS"]), principals = toset(["*"]), conditions = [{ test = "StringNotEquals", variable = "aws:PrincipalArn", values = toset(["arn:aws:iam::111122223333:role/act-teams-deployer"]) }] }]
    error_message = "planner-3: the Deny is missing, inverted, narrower than the invoke actions, or exempts other principals"
  }

  assert {
    condition     = aws_bedrockagentcore_resource_policy.runtime["planner-3"].resource_arn == "arn:aws:bedrock-agentcore:us-east-1:111122223333:runtime/act_teams_planner_3-MOCK"
    error_message = "planner-3: the resource policy is not attached to this runtime"
  }

  assert {
    condition     = length(data.aws_iam_policy_document.runtime["worker-1"].statement) == 2
    error_message = "worker-1: the runtime policy must have exactly one Allow and one Deny statement"
  }

  assert {
    condition     = [for s in data.aws_iam_policy_document.runtime["worker-1"].statement : { effect = s.effect, actions = toset(s.actions), resources = toset(s.resources), types = toset([for p in s.principals : p.type]), principals = toset(flatten([for p in s.principals : p.identifiers])) } if s.sid == "AllowListedCallers"] == [{ effect = "Allow", actions = toset(["bedrock-agentcore:InvokeAgentRuntime"]), resources = toset(["arn:aws:bedrock-agentcore:us-east-1:111122223333:runtime/act_teams_worker_1-MOCK"]), types = toset(["AWS"]), principals = toset(["arn:aws:iam::111122223333:role/act-teams/act-teams-planner-1", "arn:aws:iam::111122223333:role/act-teams/act-teams-planner-2", "arn:aws:iam::111122223333:role/act-teams/act-teams-planner-3"]) }]
    error_message = "worker-1: the Allow is not exactly the listed caller roles on this runtime"
  }

  assert {
    condition     = [for s in data.aws_iam_policy_document.runtime["worker-1"].statement : { effect = s.effect, actions = toset(s.actions), resources = toset(s.resources), types = toset([for p in s.principals : p.type]), principals = toset(flatten([for p in s.principals : p.identifiers])), conditions = [for c in s.condition : { test = c.test, variable = c.variable, values = toset(c.values) }] } if s.sid == "DenyEveryoneElse"] == [{ effect = "Deny", actions = toset(["bedrock-agentcore:InvokeAgentRuntime", "bedrock-agentcore:InvokeAgentRuntimeForUser", "bedrock-agentcore:InvokeAgentRuntimeCommand", "bedrock-agentcore:InvokeAgentRuntimeCommandShell", "bedrock-agentcore:InvokeAgentRuntimeWithWebSocketStream", "bedrock-agentcore:InvokeAgentRuntimeWithWebSocketStreamForUser", "bedrock-agentcore:StopRuntimeSession", "bedrock-agentcore:GetAgentCard"]), resources = toset(["arn:aws:bedrock-agentcore:us-east-1:111122223333:runtime/act_teams_worker_1-MOCK"]), types = toset(["AWS"]), principals = toset(["*"]), conditions = [{ test = "StringNotEquals", variable = "aws:PrincipalArn", values = toset(["arn:aws:iam::111122223333:role/act-teams/act-teams-planner-1", "arn:aws:iam::111122223333:role/act-teams/act-teams-planner-2", "arn:aws:iam::111122223333:role/act-teams/act-teams-planner-3"]) }] }]
    error_message = "worker-1: the Deny is missing, inverted, narrower than the invoke actions, or exempts other principals"
  }

  assert {
    condition     = aws_bedrockagentcore_resource_policy.runtime["worker-1"].resource_arn == "arn:aws:bedrock-agentcore:us-east-1:111122223333:runtime/act_teams_worker_1-MOCK"
    error_message = "worker-1: the resource policy is not attached to this runtime"
  }

  assert {
    condition     = length(data.aws_iam_policy_document.runtime["worker-2"].statement) == 2
    error_message = "worker-2: the runtime policy must have exactly one Allow and one Deny statement"
  }

  assert {
    condition     = [for s in data.aws_iam_policy_document.runtime["worker-2"].statement : { effect = s.effect, actions = toset(s.actions), resources = toset(s.resources), types = toset([for p in s.principals : p.type]), principals = toset(flatten([for p in s.principals : p.identifiers])) } if s.sid == "AllowListedCallers"] == [{ effect = "Allow", actions = toset(["bedrock-agentcore:InvokeAgentRuntime"]), resources = toset(["arn:aws:bedrock-agentcore:us-east-1:111122223333:runtime/act_teams_worker_2-MOCK"]), types = toset(["AWS"]), principals = toset(["arn:aws:iam::111122223333:role/act-teams/act-teams-planner-1", "arn:aws:iam::111122223333:role/act-teams/act-teams-planner-2", "arn:aws:iam::111122223333:role/act-teams/act-teams-planner-3"]) }]
    error_message = "worker-2: the Allow is not exactly the listed caller roles on this runtime"
  }

  assert {
    condition     = [for s in data.aws_iam_policy_document.runtime["worker-2"].statement : { effect = s.effect, actions = toset(s.actions), resources = toset(s.resources), types = toset([for p in s.principals : p.type]), principals = toset(flatten([for p in s.principals : p.identifiers])), conditions = [for c in s.condition : { test = c.test, variable = c.variable, values = toset(c.values) }] } if s.sid == "DenyEveryoneElse"] == [{ effect = "Deny", actions = toset(["bedrock-agentcore:InvokeAgentRuntime", "bedrock-agentcore:InvokeAgentRuntimeForUser", "bedrock-agentcore:InvokeAgentRuntimeCommand", "bedrock-agentcore:InvokeAgentRuntimeCommandShell", "bedrock-agentcore:InvokeAgentRuntimeWithWebSocketStream", "bedrock-agentcore:InvokeAgentRuntimeWithWebSocketStreamForUser", "bedrock-agentcore:StopRuntimeSession", "bedrock-agentcore:GetAgentCard"]), resources = toset(["arn:aws:bedrock-agentcore:us-east-1:111122223333:runtime/act_teams_worker_2-MOCK"]), types = toset(["AWS"]), principals = toset(["*"]), conditions = [{ test = "StringNotEquals", variable = "aws:PrincipalArn", values = toset(["arn:aws:iam::111122223333:role/act-teams/act-teams-planner-1", "arn:aws:iam::111122223333:role/act-teams/act-teams-planner-2", "arn:aws:iam::111122223333:role/act-teams/act-teams-planner-3"]) }] }]
    error_message = "worker-2: the Deny is missing, inverted, narrower than the invoke actions, or exempts other principals"
  }

  assert {
    condition     = aws_bedrockagentcore_resource_policy.runtime["worker-2"].resource_arn == "arn:aws:bedrock-agentcore:us-east-1:111122223333:runtime/act_teams_worker_2-MOCK"
    error_message = "worker-2: the resource policy is not attached to this runtime"
  }

  assert {
    condition     = length(data.aws_iam_policy_document.runtime["worker-3"].statement) == 2
    error_message = "worker-3: the runtime policy must have exactly one Allow and one Deny statement"
  }

  assert {
    condition     = [for s in data.aws_iam_policy_document.runtime["worker-3"].statement : { effect = s.effect, actions = toset(s.actions), resources = toset(s.resources), types = toset([for p in s.principals : p.type]), principals = toset(flatten([for p in s.principals : p.identifiers])) } if s.sid == "AllowListedCallers"] == [{ effect = "Allow", actions = toset(["bedrock-agentcore:InvokeAgentRuntime"]), resources = toset(["arn:aws:bedrock-agentcore:us-east-1:111122223333:runtime/act_teams_worker_3-MOCK"]), types = toset(["AWS"]), principals = toset(["arn:aws:iam::111122223333:role/act-teams/act-teams-planner-1", "arn:aws:iam::111122223333:role/act-teams/act-teams-planner-2", "arn:aws:iam::111122223333:role/act-teams/act-teams-planner-3"]) }]
    error_message = "worker-3: the Allow is not exactly the listed caller roles on this runtime"
  }

  assert {
    condition     = [for s in data.aws_iam_policy_document.runtime["worker-3"].statement : { effect = s.effect, actions = toset(s.actions), resources = toset(s.resources), types = toset([for p in s.principals : p.type]), principals = toset(flatten([for p in s.principals : p.identifiers])), conditions = [for c in s.condition : { test = c.test, variable = c.variable, values = toset(c.values) }] } if s.sid == "DenyEveryoneElse"] == [{ effect = "Deny", actions = toset(["bedrock-agentcore:InvokeAgentRuntime", "bedrock-agentcore:InvokeAgentRuntimeForUser", "bedrock-agentcore:InvokeAgentRuntimeCommand", "bedrock-agentcore:InvokeAgentRuntimeCommandShell", "bedrock-agentcore:InvokeAgentRuntimeWithWebSocketStream", "bedrock-agentcore:InvokeAgentRuntimeWithWebSocketStreamForUser", "bedrock-agentcore:StopRuntimeSession", "bedrock-agentcore:GetAgentCard"]), resources = toset(["arn:aws:bedrock-agentcore:us-east-1:111122223333:runtime/act_teams_worker_3-MOCK"]), types = toset(["AWS"]), principals = toset(["*"]), conditions = [{ test = "StringNotEquals", variable = "aws:PrincipalArn", values = toset(["arn:aws:iam::111122223333:role/act-teams/act-teams-planner-1", "arn:aws:iam::111122223333:role/act-teams/act-teams-planner-2", "arn:aws:iam::111122223333:role/act-teams/act-teams-planner-3"]) }] }]
    error_message = "worker-3: the Deny is missing, inverted, narrower than the invoke actions, or exempts other principals"
  }

  assert {
    condition     = aws_bedrockagentcore_resource_policy.runtime["worker-3"].resource_arn == "arn:aws:bedrock-agentcore:us-east-1:111122223333:runtime/act_teams_worker_3-MOCK"
    error_message = "worker-3: the resource policy is not attached to this runtime"
  }

  assert {
    condition     = length(data.aws_iam_policy_document.runtime["reviewer-1"].statement) == 2
    error_message = "reviewer-1: the runtime policy must have exactly one Allow and one Deny statement"
  }

  assert {
    condition     = [for s in data.aws_iam_policy_document.runtime["reviewer-1"].statement : { effect = s.effect, actions = toset(s.actions), resources = toset(s.resources), types = toset([for p in s.principals : p.type]), principals = toset(flatten([for p in s.principals : p.identifiers])) } if s.sid == "AllowListedCallers"] == [{ effect = "Allow", actions = toset(["bedrock-agentcore:InvokeAgentRuntime"]), resources = toset(["arn:aws:bedrock-agentcore:us-east-1:111122223333:runtime/act_teams_reviewer_1-MOCK"]), types = toset(["AWS"]), principals = toset(["arn:aws:iam::111122223333:role/act-teams/act-teams-worker-1", "arn:aws:iam::111122223333:role/act-teams/act-teams-worker-2", "arn:aws:iam::111122223333:role/act-teams/act-teams-worker-3", "arn:aws:iam::111122223333:role/act-teams/act-teams-planner-1"]) }]
    error_message = "reviewer-1: the Allow is not exactly the listed caller roles on this runtime"
  }

  assert {
    condition     = [for s in data.aws_iam_policy_document.runtime["reviewer-1"].statement : { effect = s.effect, actions = toset(s.actions), resources = toset(s.resources), types = toset([for p in s.principals : p.type]), principals = toset(flatten([for p in s.principals : p.identifiers])), conditions = [for c in s.condition : { test = c.test, variable = c.variable, values = toset(c.values) }] } if s.sid == "DenyEveryoneElse"] == [{ effect = "Deny", actions = toset(["bedrock-agentcore:InvokeAgentRuntime", "bedrock-agentcore:InvokeAgentRuntimeForUser", "bedrock-agentcore:InvokeAgentRuntimeCommand", "bedrock-agentcore:InvokeAgentRuntimeCommandShell", "bedrock-agentcore:InvokeAgentRuntimeWithWebSocketStream", "bedrock-agentcore:InvokeAgentRuntimeWithWebSocketStreamForUser", "bedrock-agentcore:StopRuntimeSession", "bedrock-agentcore:GetAgentCard"]), resources = toset(["arn:aws:bedrock-agentcore:us-east-1:111122223333:runtime/act_teams_reviewer_1-MOCK"]), types = toset(["AWS"]), principals = toset(["*"]), conditions = [{ test = "StringNotEquals", variable = "aws:PrincipalArn", values = toset(["arn:aws:iam::111122223333:role/act-teams/act-teams-worker-1", "arn:aws:iam::111122223333:role/act-teams/act-teams-worker-2", "arn:aws:iam::111122223333:role/act-teams/act-teams-worker-3", "arn:aws:iam::111122223333:role/act-teams/act-teams-planner-1"]) }] }]
    error_message = "reviewer-1: the Deny is missing, inverted, narrower than the invoke actions, or exempts other principals"
  }

  assert {
    condition     = aws_bedrockagentcore_resource_policy.runtime["reviewer-1"].resource_arn == "arn:aws:bedrock-agentcore:us-east-1:111122223333:runtime/act_teams_reviewer_1-MOCK"
    error_message = "reviewer-1: the resource policy is not attached to this runtime"
  }

  assert {
    condition     = length(data.aws_iam_policy_document.runtime["reviewer-2"].statement) == 2
    error_message = "reviewer-2: the runtime policy must have exactly one Allow and one Deny statement"
  }

  assert {
    condition     = [for s in data.aws_iam_policy_document.runtime["reviewer-2"].statement : { effect = s.effect, actions = toset(s.actions), resources = toset(s.resources), types = toset([for p in s.principals : p.type]), principals = toset(flatten([for p in s.principals : p.identifiers])) } if s.sid == "AllowListedCallers"] == [{ effect = "Allow", actions = toset(["bedrock-agentcore:InvokeAgentRuntime"]), resources = toset(["arn:aws:bedrock-agentcore:us-east-1:111122223333:runtime/act_teams_reviewer_2-MOCK"]), types = toset(["AWS"]), principals = toset(["arn:aws:iam::111122223333:role/act-teams/act-teams-worker-1", "arn:aws:iam::111122223333:role/act-teams/act-teams-worker-2", "arn:aws:iam::111122223333:role/act-teams/act-teams-worker-3"]) }]
    error_message = "reviewer-2: the Allow is not exactly the listed caller roles on this runtime"
  }

  assert {
    condition     = [for s in data.aws_iam_policy_document.runtime["reviewer-2"].statement : { effect = s.effect, actions = toset(s.actions), resources = toset(s.resources), types = toset([for p in s.principals : p.type]), principals = toset(flatten([for p in s.principals : p.identifiers])), conditions = [for c in s.condition : { test = c.test, variable = c.variable, values = toset(c.values) }] } if s.sid == "DenyEveryoneElse"] == [{ effect = "Deny", actions = toset(["bedrock-agentcore:InvokeAgentRuntime", "bedrock-agentcore:InvokeAgentRuntimeForUser", "bedrock-agentcore:InvokeAgentRuntimeCommand", "bedrock-agentcore:InvokeAgentRuntimeCommandShell", "bedrock-agentcore:InvokeAgentRuntimeWithWebSocketStream", "bedrock-agentcore:InvokeAgentRuntimeWithWebSocketStreamForUser", "bedrock-agentcore:StopRuntimeSession", "bedrock-agentcore:GetAgentCard"]), resources = toset(["arn:aws:bedrock-agentcore:us-east-1:111122223333:runtime/act_teams_reviewer_2-MOCK"]), types = toset(["AWS"]), principals = toset(["*"]), conditions = [{ test = "StringNotEquals", variable = "aws:PrincipalArn", values = toset(["arn:aws:iam::111122223333:role/act-teams/act-teams-worker-1", "arn:aws:iam::111122223333:role/act-teams/act-teams-worker-2", "arn:aws:iam::111122223333:role/act-teams/act-teams-worker-3"]) }] }]
    error_message = "reviewer-2: the Deny is missing, inverted, narrower than the invoke actions, or exempts other principals"
  }

  assert {
    condition     = aws_bedrockagentcore_resource_policy.runtime["reviewer-2"].resource_arn == "arn:aws:bedrock-agentcore:us-east-1:111122223333:runtime/act_teams_reviewer_2-MOCK"
    error_message = "reviewer-2: the resource policy is not attached to this runtime"
  }

  assert {
    condition     = length(data.aws_iam_policy_document.runtime["reviewer-3"].statement) == 2
    error_message = "reviewer-3: the runtime policy must have exactly one Allow and one Deny statement"
  }

  assert {
    condition     = [for s in data.aws_iam_policy_document.runtime["reviewer-3"].statement : { effect = s.effect, actions = toset(s.actions), resources = toset(s.resources), types = toset([for p in s.principals : p.type]), principals = toset(flatten([for p in s.principals : p.identifiers])) } if s.sid == "AllowListedCallers"] == [{ effect = "Allow", actions = toset(["bedrock-agentcore:InvokeAgentRuntime"]), resources = toset(["arn:aws:bedrock-agentcore:us-east-1:111122223333:runtime/act_teams_reviewer_3-MOCK"]), types = toset(["AWS"]), principals = toset(["arn:aws:iam::111122223333:role/act-teams/act-teams-worker-1", "arn:aws:iam::111122223333:role/act-teams/act-teams-worker-2", "arn:aws:iam::111122223333:role/act-teams/act-teams-worker-3"]) }]
    error_message = "reviewer-3: the Allow is not exactly the listed caller roles on this runtime"
  }

  assert {
    condition     = [for s in data.aws_iam_policy_document.runtime["reviewer-3"].statement : { effect = s.effect, actions = toset(s.actions), resources = toset(s.resources), types = toset([for p in s.principals : p.type]), principals = toset(flatten([for p in s.principals : p.identifiers])), conditions = [for c in s.condition : { test = c.test, variable = c.variable, values = toset(c.values) }] } if s.sid == "DenyEveryoneElse"] == [{ effect = "Deny", actions = toset(["bedrock-agentcore:InvokeAgentRuntime", "bedrock-agentcore:InvokeAgentRuntimeForUser", "bedrock-agentcore:InvokeAgentRuntimeCommand", "bedrock-agentcore:InvokeAgentRuntimeCommandShell", "bedrock-agentcore:InvokeAgentRuntimeWithWebSocketStream", "bedrock-agentcore:InvokeAgentRuntimeWithWebSocketStreamForUser", "bedrock-agentcore:StopRuntimeSession", "bedrock-agentcore:GetAgentCard"]), resources = toset(["arn:aws:bedrock-agentcore:us-east-1:111122223333:runtime/act_teams_reviewer_3-MOCK"]), types = toset(["AWS"]), principals = toset(["*"]), conditions = [{ test = "StringNotEquals", variable = "aws:PrincipalArn", values = toset(["arn:aws:iam::111122223333:role/act-teams/act-teams-worker-1", "arn:aws:iam::111122223333:role/act-teams/act-teams-worker-2", "arn:aws:iam::111122223333:role/act-teams/act-teams-worker-3"]) }] }]
    error_message = "reviewer-3: the Deny is missing, inverted, narrower than the invoke actions, or exempts other principals"
  }

  assert {
    condition     = aws_bedrockagentcore_resource_policy.runtime["reviewer-3"].resource_arn == "arn:aws:bedrock-agentcore:us-east-1:111122223333:runtime/act_teams_reviewer_3-MOCK"
    error_message = "reviewer-3: the resource policy is not attached to this runtime"
  }

}

# AWS layer 1: each caller may invoke exactly its allowed peers (reviewers have no peer and no policy).
run "invoke_policy_is_exactly_the_allowed_peers" {
  command = apply

  assert {
    condition     = toset(keys(data.aws_iam_policy_document.invoke)) == toset(["planner-1", "planner-2", "planner-3", "worker-1", "worker-2", "worker-3"]) && toset(keys(aws_iam_role_policy.invoke)) == toset(["planner-1", "planner-2", "planner-3", "worker-1", "worker-2", "worker-3"])
    error_message = "only agents with an allowed peer get an invoke policy"
  }

  assert {
    condition     = [for s in data.aws_iam_policy_document.invoke["planner-1"].statement : { sid = s.sid, effect = coalesce(s.effect, "Allow"), actions = toset(s.actions), resources = toset(s.resources) }] == [{ sid = "InvokeAllowedPeersOnly", effect = "Allow", actions = toset(["bedrock-agentcore:InvokeAgentRuntime"]), resources = toset(["arn:aws:bedrock-agentcore:us-east-1:111122223333:runtime/act_teams_worker_1-MOCK", "arn:aws:bedrock-agentcore:us-east-1:111122223333:runtime/act_teams_worker_1-MOCK/*", "arn:aws:bedrock-agentcore:us-east-1:111122223333:runtime/act_teams_worker_2-MOCK", "arn:aws:bedrock-agentcore:us-east-1:111122223333:runtime/act_teams_worker_2-MOCK/*", "arn:aws:bedrock-agentcore:us-east-1:111122223333:runtime/act_teams_worker_3-MOCK", "arn:aws:bedrock-agentcore:us-east-1:111122223333:runtime/act_teams_worker_3-MOCK/*", "arn:aws:bedrock-agentcore:us-east-1:111122223333:runtime/act_teams_reviewer_1-MOCK", "arn:aws:bedrock-agentcore:us-east-1:111122223333:runtime/act_teams_reviewer_1-MOCK/*"]) }]
    error_message = "planner-1: the invoke policy is not exactly its allowed peers"
  }

  assert {
    condition     = [for s in data.aws_iam_policy_document.invoke["planner-2"].statement : { sid = s.sid, effect = coalesce(s.effect, "Allow"), actions = toset(s.actions), resources = toset(s.resources) }] == [{ sid = "InvokeAllowedPeersOnly", effect = "Allow", actions = toset(["bedrock-agentcore:InvokeAgentRuntime"]), resources = toset(["arn:aws:bedrock-agentcore:us-east-1:111122223333:runtime/act_teams_worker_1-MOCK", "arn:aws:bedrock-agentcore:us-east-1:111122223333:runtime/act_teams_worker_1-MOCK/*", "arn:aws:bedrock-agentcore:us-east-1:111122223333:runtime/act_teams_worker_2-MOCK", "arn:aws:bedrock-agentcore:us-east-1:111122223333:runtime/act_teams_worker_2-MOCK/*", "arn:aws:bedrock-agentcore:us-east-1:111122223333:runtime/act_teams_worker_3-MOCK", "arn:aws:bedrock-agentcore:us-east-1:111122223333:runtime/act_teams_worker_3-MOCK/*"]) }]
    error_message = "planner-2: the invoke policy is not exactly its allowed peers"
  }

  assert {
    condition     = [for s in data.aws_iam_policy_document.invoke["planner-3"].statement : { sid = s.sid, effect = coalesce(s.effect, "Allow"), actions = toset(s.actions), resources = toset(s.resources) }] == [{ sid = "InvokeAllowedPeersOnly", effect = "Allow", actions = toset(["bedrock-agentcore:InvokeAgentRuntime"]), resources = toset(["arn:aws:bedrock-agentcore:us-east-1:111122223333:runtime/act_teams_worker_1-MOCK", "arn:aws:bedrock-agentcore:us-east-1:111122223333:runtime/act_teams_worker_1-MOCK/*", "arn:aws:bedrock-agentcore:us-east-1:111122223333:runtime/act_teams_worker_2-MOCK", "arn:aws:bedrock-agentcore:us-east-1:111122223333:runtime/act_teams_worker_2-MOCK/*", "arn:aws:bedrock-agentcore:us-east-1:111122223333:runtime/act_teams_worker_3-MOCK", "arn:aws:bedrock-agentcore:us-east-1:111122223333:runtime/act_teams_worker_3-MOCK/*"]) }]
    error_message = "planner-3: the invoke policy is not exactly its allowed peers"
  }

  assert {
    condition     = [for s in data.aws_iam_policy_document.invoke["worker-1"].statement : { sid = s.sid, effect = coalesce(s.effect, "Allow"), actions = toset(s.actions), resources = toset(s.resources) }] == [{ sid = "InvokeAllowedPeersOnly", effect = "Allow", actions = toset(["bedrock-agentcore:InvokeAgentRuntime"]), resources = toset(["arn:aws:bedrock-agentcore:us-east-1:111122223333:runtime/act_teams_reviewer_1-MOCK", "arn:aws:bedrock-agentcore:us-east-1:111122223333:runtime/act_teams_reviewer_1-MOCK/*", "arn:aws:bedrock-agentcore:us-east-1:111122223333:runtime/act_teams_reviewer_2-MOCK", "arn:aws:bedrock-agentcore:us-east-1:111122223333:runtime/act_teams_reviewer_2-MOCK/*", "arn:aws:bedrock-agentcore:us-east-1:111122223333:runtime/act_teams_reviewer_3-MOCK", "arn:aws:bedrock-agentcore:us-east-1:111122223333:runtime/act_teams_reviewer_3-MOCK/*"]) }]
    error_message = "worker-1: the invoke policy is not exactly its allowed peers"
  }

  assert {
    condition     = [for s in data.aws_iam_policy_document.invoke["worker-2"].statement : { sid = s.sid, effect = coalesce(s.effect, "Allow"), actions = toset(s.actions), resources = toset(s.resources) }] == [{ sid = "InvokeAllowedPeersOnly", effect = "Allow", actions = toset(["bedrock-agentcore:InvokeAgentRuntime"]), resources = toset(["arn:aws:bedrock-agentcore:us-east-1:111122223333:runtime/act_teams_reviewer_1-MOCK", "arn:aws:bedrock-agentcore:us-east-1:111122223333:runtime/act_teams_reviewer_1-MOCK/*", "arn:aws:bedrock-agentcore:us-east-1:111122223333:runtime/act_teams_reviewer_2-MOCK", "arn:aws:bedrock-agentcore:us-east-1:111122223333:runtime/act_teams_reviewer_2-MOCK/*", "arn:aws:bedrock-agentcore:us-east-1:111122223333:runtime/act_teams_reviewer_3-MOCK", "arn:aws:bedrock-agentcore:us-east-1:111122223333:runtime/act_teams_reviewer_3-MOCK/*"]) }]
    error_message = "worker-2: the invoke policy is not exactly its allowed peers"
  }

  assert {
    condition     = [for s in data.aws_iam_policy_document.invoke["worker-3"].statement : { sid = s.sid, effect = coalesce(s.effect, "Allow"), actions = toset(s.actions), resources = toset(s.resources) }] == [{ sid = "InvokeAllowedPeersOnly", effect = "Allow", actions = toset(["bedrock-agentcore:InvokeAgentRuntime"]), resources = toset(["arn:aws:bedrock-agentcore:us-east-1:111122223333:runtime/act_teams_reviewer_1-MOCK", "arn:aws:bedrock-agentcore:us-east-1:111122223333:runtime/act_teams_reviewer_1-MOCK/*", "arn:aws:bedrock-agentcore:us-east-1:111122223333:runtime/act_teams_reviewer_2-MOCK", "arn:aws:bedrock-agentcore:us-east-1:111122223333:runtime/act_teams_reviewer_2-MOCK/*", "arn:aws:bedrock-agentcore:us-east-1:111122223333:runtime/act_teams_reviewer_3-MOCK", "arn:aws:bedrock-agentcore:us-east-1:111122223333:runtime/act_teams_reviewer_3-MOCK/*"]) }]
    error_message = "worker-3: the invoke policy is not exactly its allowed peers"
  }

}

# Base role: no model invocation (models come from OpenRouter), no wildcard action, no bare "*" resource.
run "base_role_has_no_model_or_wildcard_rights" {
  command = apply

  assert {
    condition     = toset([for s in data.aws_iam_policy_document.base["planner-1"].statement : s.sid]) == toset(["OwnLogs", "OwnPeerMapAndCode", "ReadOpenRouterKey", "ReadRunToken", "OwnWorkloadIdentityToken"]) && toset(flatten([for s in data.aws_iam_policy_document.base["planner-1"].statement : s.actions])) == toset(["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents", "logs:DescribeLogStreams", "s3:GetObject", "secretsmanager:GetSecretValue", "bedrock-agentcore:GetWorkloadAccessToken", "bedrock-agentcore:GetWorkloadAccessTokenForJWT", "bedrock-agentcore:GetWorkloadAccessTokenForUserId"])
    error_message = "planner-1: the base role has an action or statement that is not on the reviewed list (for example bedrock:InvokeModel)"
  }

  assert {
    condition     = !anytrue([for s in data.aws_iam_policy_document.base["planner-1"].statement : anytrue([for r in s.resources : r == "*"])]) && alltrue([for s in data.aws_iam_policy_document.base["planner-1"].statement : coalesce(s.effect, "Allow") == "Allow"])
    error_message = "planner-1: the base role has a bare wildcard resource or a non-Allow statement"
  }

  assert {
    condition     = toset([for s in data.aws_iam_policy_document.base["planner-2"].statement : s.sid]) == toset(["OwnLogs", "OwnPeerMapAndCode", "ReadOpenRouterKey", "ReadRunToken", "OwnWorkloadIdentityToken"]) && toset(flatten([for s in data.aws_iam_policy_document.base["planner-2"].statement : s.actions])) == toset(["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents", "logs:DescribeLogStreams", "s3:GetObject", "secretsmanager:GetSecretValue", "bedrock-agentcore:GetWorkloadAccessToken", "bedrock-agentcore:GetWorkloadAccessTokenForJWT", "bedrock-agentcore:GetWorkloadAccessTokenForUserId"])
    error_message = "planner-2: the base role has an action or statement that is not on the reviewed list (for example bedrock:InvokeModel)"
  }

  assert {
    condition     = !anytrue([for s in data.aws_iam_policy_document.base["planner-2"].statement : anytrue([for r in s.resources : r == "*"])]) && alltrue([for s in data.aws_iam_policy_document.base["planner-2"].statement : coalesce(s.effect, "Allow") == "Allow"])
    error_message = "planner-2: the base role has a bare wildcard resource or a non-Allow statement"
  }

  assert {
    condition     = toset([for s in data.aws_iam_policy_document.base["planner-3"].statement : s.sid]) == toset(["OwnLogs", "OwnPeerMapAndCode", "ReadOpenRouterKey", "ReadRunToken", "OwnWorkloadIdentityToken"]) && toset(flatten([for s in data.aws_iam_policy_document.base["planner-3"].statement : s.actions])) == toset(["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents", "logs:DescribeLogStreams", "s3:GetObject", "secretsmanager:GetSecretValue", "bedrock-agentcore:GetWorkloadAccessToken", "bedrock-agentcore:GetWorkloadAccessTokenForJWT", "bedrock-agentcore:GetWorkloadAccessTokenForUserId"])
    error_message = "planner-3: the base role has an action or statement that is not on the reviewed list (for example bedrock:InvokeModel)"
  }

  assert {
    condition     = !anytrue([for s in data.aws_iam_policy_document.base["planner-3"].statement : anytrue([for r in s.resources : r == "*"])]) && alltrue([for s in data.aws_iam_policy_document.base["planner-3"].statement : coalesce(s.effect, "Allow") == "Allow"])
    error_message = "planner-3: the base role has a bare wildcard resource or a non-Allow statement"
  }

  assert {
    condition     = toset([for s in data.aws_iam_policy_document.base["worker-1"].statement : s.sid]) == toset(["OwnLogs", "OwnPeerMapAndCode", "ReadOpenRouterKey", "ReadRunToken", "OwnWorkloadIdentityToken"]) && toset(flatten([for s in data.aws_iam_policy_document.base["worker-1"].statement : s.actions])) == toset(["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents", "logs:DescribeLogStreams", "s3:GetObject", "secretsmanager:GetSecretValue", "bedrock-agentcore:GetWorkloadAccessToken", "bedrock-agentcore:GetWorkloadAccessTokenForJWT", "bedrock-agentcore:GetWorkloadAccessTokenForUserId"])
    error_message = "worker-1: the base role has an action or statement that is not on the reviewed list (for example bedrock:InvokeModel)"
  }

  assert {
    condition     = !anytrue([for s in data.aws_iam_policy_document.base["worker-1"].statement : anytrue([for r in s.resources : r == "*"])]) && alltrue([for s in data.aws_iam_policy_document.base["worker-1"].statement : coalesce(s.effect, "Allow") == "Allow"])
    error_message = "worker-1: the base role has a bare wildcard resource or a non-Allow statement"
  }

  assert {
    condition     = toset([for s in data.aws_iam_policy_document.base["worker-2"].statement : s.sid]) == toset(["OwnLogs", "OwnPeerMapAndCode", "ReadOpenRouterKey", "ReadRunToken", "OwnWorkloadIdentityToken"]) && toset(flatten([for s in data.aws_iam_policy_document.base["worker-2"].statement : s.actions])) == toset(["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents", "logs:DescribeLogStreams", "s3:GetObject", "secretsmanager:GetSecretValue", "bedrock-agentcore:GetWorkloadAccessToken", "bedrock-agentcore:GetWorkloadAccessTokenForJWT", "bedrock-agentcore:GetWorkloadAccessTokenForUserId"])
    error_message = "worker-2: the base role has an action or statement that is not on the reviewed list (for example bedrock:InvokeModel)"
  }

  assert {
    condition     = !anytrue([for s in data.aws_iam_policy_document.base["worker-2"].statement : anytrue([for r in s.resources : r == "*"])]) && alltrue([for s in data.aws_iam_policy_document.base["worker-2"].statement : coalesce(s.effect, "Allow") == "Allow"])
    error_message = "worker-2: the base role has a bare wildcard resource or a non-Allow statement"
  }

  assert {
    condition     = toset([for s in data.aws_iam_policy_document.base["worker-3"].statement : s.sid]) == toset(["OwnLogs", "OwnPeerMapAndCode", "ReadOpenRouterKey", "ReadRunToken", "OwnWorkloadIdentityToken"]) && toset(flatten([for s in data.aws_iam_policy_document.base["worker-3"].statement : s.actions])) == toset(["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents", "logs:DescribeLogStreams", "s3:GetObject", "secretsmanager:GetSecretValue", "bedrock-agentcore:GetWorkloadAccessToken", "bedrock-agentcore:GetWorkloadAccessTokenForJWT", "bedrock-agentcore:GetWorkloadAccessTokenForUserId"])
    error_message = "worker-3: the base role has an action or statement that is not on the reviewed list (for example bedrock:InvokeModel)"
  }

  assert {
    condition     = !anytrue([for s in data.aws_iam_policy_document.base["worker-3"].statement : anytrue([for r in s.resources : r == "*"])]) && alltrue([for s in data.aws_iam_policy_document.base["worker-3"].statement : coalesce(s.effect, "Allow") == "Allow"])
    error_message = "worker-3: the base role has a bare wildcard resource or a non-Allow statement"
  }

  assert {
    condition     = toset([for s in data.aws_iam_policy_document.base["reviewer-1"].statement : s.sid]) == toset(["OwnLogs", "OwnPeerMapAndCode", "ReadOpenRouterKey", "ReadRunToken", "OwnWorkloadIdentityToken"]) && toset(flatten([for s in data.aws_iam_policy_document.base["reviewer-1"].statement : s.actions])) == toset(["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents", "logs:DescribeLogStreams", "s3:GetObject", "secretsmanager:GetSecretValue", "bedrock-agentcore:GetWorkloadAccessToken", "bedrock-agentcore:GetWorkloadAccessTokenForJWT", "bedrock-agentcore:GetWorkloadAccessTokenForUserId"])
    error_message = "reviewer-1: the base role has an action or statement that is not on the reviewed list (for example bedrock:InvokeModel)"
  }

  assert {
    condition     = !anytrue([for s in data.aws_iam_policy_document.base["reviewer-1"].statement : anytrue([for r in s.resources : r == "*"])]) && alltrue([for s in data.aws_iam_policy_document.base["reviewer-1"].statement : coalesce(s.effect, "Allow") == "Allow"])
    error_message = "reviewer-1: the base role has a bare wildcard resource or a non-Allow statement"
  }

  assert {
    condition     = toset([for s in data.aws_iam_policy_document.base["reviewer-2"].statement : s.sid]) == toset(["OwnLogs", "OwnPeerMapAndCode", "ReadOpenRouterKey", "ReadRunToken", "OwnWorkloadIdentityToken"]) && toset(flatten([for s in data.aws_iam_policy_document.base["reviewer-2"].statement : s.actions])) == toset(["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents", "logs:DescribeLogStreams", "s3:GetObject", "secretsmanager:GetSecretValue", "bedrock-agentcore:GetWorkloadAccessToken", "bedrock-agentcore:GetWorkloadAccessTokenForJWT", "bedrock-agentcore:GetWorkloadAccessTokenForUserId"])
    error_message = "reviewer-2: the base role has an action or statement that is not on the reviewed list (for example bedrock:InvokeModel)"
  }

  assert {
    condition     = !anytrue([for s in data.aws_iam_policy_document.base["reviewer-2"].statement : anytrue([for r in s.resources : r == "*"])]) && alltrue([for s in data.aws_iam_policy_document.base["reviewer-2"].statement : coalesce(s.effect, "Allow") == "Allow"])
    error_message = "reviewer-2: the base role has a bare wildcard resource or a non-Allow statement"
  }

  assert {
    condition     = toset([for s in data.aws_iam_policy_document.base["reviewer-3"].statement : s.sid]) == toset(["OwnLogs", "OwnPeerMapAndCode", "ReadOpenRouterKey", "ReadRunToken", "OwnWorkloadIdentityToken"]) && toset(flatten([for s in data.aws_iam_policy_document.base["reviewer-3"].statement : s.actions])) == toset(["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents", "logs:DescribeLogStreams", "s3:GetObject", "secretsmanager:GetSecretValue", "bedrock-agentcore:GetWorkloadAccessToken", "bedrock-agentcore:GetWorkloadAccessTokenForJWT", "bedrock-agentcore:GetWorkloadAccessTokenForUserId"])
    error_message = "reviewer-3: the base role has an action or statement that is not on the reviewed list (for example bedrock:InvokeModel)"
  }

  assert {
    condition     = !anytrue([for s in data.aws_iam_policy_document.base["reviewer-3"].statement : anytrue([for r in s.resources : r == "*"])]) && alltrue([for s in data.aws_iam_policy_document.base["reviewer-3"].statement : coalesce(s.effect, "Allow") == "Allow"])
    error_message = "reviewer-3: the base role has a bare wildcard resource or a non-Allow statement"
  }

  assert {
    condition     = { for s in data.aws_iam_policy_document.base["planner-1"].statement : s.sid => toset(s.resources) } == { OwnLogs = toset(["arn:aws:logs:us-east-1:111122223333:log-group:/aws/bedrock-agentcore/runtimes/act_teams_planner_1-*", "arn:aws:logs:us-east-1:111122223333:log-group:/aws/bedrock-agentcore/runtimes/act_teams_planner_1-*:*"]), OwnPeerMapAndCode = toset(["arn:aws:s3:::act-teams-code-111122223333/peers/planner-1.json", "arn:aws:s3:::act-teams-code-111122223333/code/agent.zip"]), ReadOpenRouterKey = toset(["arn:aws:secretsmanager:us-east-1:111122223333:secret:act-teams/openrouter-AbCdEf"]), ReadRunToken = toset(["arn:aws:secretsmanager:us-east-1:111122223333:secret:act-teams/run-token-GhIjKl"]), OwnWorkloadIdentityToken = toset(["arn:aws:bedrock-agentcore:us-east-1:111122223333:workload-identity-directory/default", "arn:aws:bedrock-agentcore:us-east-1:111122223333:workload-identity-directory/default/workload-identity/act_teams_planner_1-*"]) }
    error_message = "planner-1: a base-role statement has resources other than the reviewed ARNs (own logs, own peer map and the code zip, the OpenRouter secret, own workload identity)"
  }

  assert {
    condition     = { for s in data.aws_iam_policy_document.base["planner-2"].statement : s.sid => toset(s.resources) } == { OwnLogs = toset(["arn:aws:logs:us-east-1:111122223333:log-group:/aws/bedrock-agentcore/runtimes/act_teams_planner_2-*", "arn:aws:logs:us-east-1:111122223333:log-group:/aws/bedrock-agentcore/runtimes/act_teams_planner_2-*:*"]), OwnPeerMapAndCode = toset(["arn:aws:s3:::act-teams-code-111122223333/peers/planner-2.json", "arn:aws:s3:::act-teams-code-111122223333/code/agent.zip"]), ReadOpenRouterKey = toset(["arn:aws:secretsmanager:us-east-1:111122223333:secret:act-teams/openrouter-AbCdEf"]), ReadRunToken = toset(["arn:aws:secretsmanager:us-east-1:111122223333:secret:act-teams/run-token-GhIjKl"]), OwnWorkloadIdentityToken = toset(["arn:aws:bedrock-agentcore:us-east-1:111122223333:workload-identity-directory/default", "arn:aws:bedrock-agentcore:us-east-1:111122223333:workload-identity-directory/default/workload-identity/act_teams_planner_2-*"]) }
    error_message = "planner-2: a base-role statement has resources other than the reviewed ARNs (own logs, own peer map and the code zip, the OpenRouter secret, own workload identity)"
  }

  assert {
    condition     = { for s in data.aws_iam_policy_document.base["planner-3"].statement : s.sid => toset(s.resources) } == { OwnLogs = toset(["arn:aws:logs:us-east-1:111122223333:log-group:/aws/bedrock-agentcore/runtimes/act_teams_planner_3-*", "arn:aws:logs:us-east-1:111122223333:log-group:/aws/bedrock-agentcore/runtimes/act_teams_planner_3-*:*"]), OwnPeerMapAndCode = toset(["arn:aws:s3:::act-teams-code-111122223333/peers/planner-3.json", "arn:aws:s3:::act-teams-code-111122223333/code/agent.zip"]), ReadOpenRouterKey = toset(["arn:aws:secretsmanager:us-east-1:111122223333:secret:act-teams/openrouter-AbCdEf"]), ReadRunToken = toset(["arn:aws:secretsmanager:us-east-1:111122223333:secret:act-teams/run-token-GhIjKl"]), OwnWorkloadIdentityToken = toset(["arn:aws:bedrock-agentcore:us-east-1:111122223333:workload-identity-directory/default", "arn:aws:bedrock-agentcore:us-east-1:111122223333:workload-identity-directory/default/workload-identity/act_teams_planner_3-*"]) }
    error_message = "planner-3: a base-role statement has resources other than the reviewed ARNs (own logs, own peer map and the code zip, the OpenRouter secret, own workload identity)"
  }

  assert {
    condition     = { for s in data.aws_iam_policy_document.base["worker-1"].statement : s.sid => toset(s.resources) } == { OwnLogs = toset(["arn:aws:logs:us-east-1:111122223333:log-group:/aws/bedrock-agentcore/runtimes/act_teams_worker_1-*", "arn:aws:logs:us-east-1:111122223333:log-group:/aws/bedrock-agentcore/runtimes/act_teams_worker_1-*:*"]), OwnPeerMapAndCode = toset(["arn:aws:s3:::act-teams-code-111122223333/peers/worker-1.json", "arn:aws:s3:::act-teams-code-111122223333/code/agent.zip"]), ReadOpenRouterKey = toset(["arn:aws:secretsmanager:us-east-1:111122223333:secret:act-teams/openrouter-AbCdEf"]), ReadRunToken = toset(["arn:aws:secretsmanager:us-east-1:111122223333:secret:act-teams/run-token-GhIjKl"]), OwnWorkloadIdentityToken = toset(["arn:aws:bedrock-agentcore:us-east-1:111122223333:workload-identity-directory/default", "arn:aws:bedrock-agentcore:us-east-1:111122223333:workload-identity-directory/default/workload-identity/act_teams_worker_1-*"]) }
    error_message = "worker-1: a base-role statement has resources other than the reviewed ARNs (own logs, own peer map and the code zip, the OpenRouter secret, own workload identity)"
  }

  assert {
    condition     = { for s in data.aws_iam_policy_document.base["worker-2"].statement : s.sid => toset(s.resources) } == { OwnLogs = toset(["arn:aws:logs:us-east-1:111122223333:log-group:/aws/bedrock-agentcore/runtimes/act_teams_worker_2-*", "arn:aws:logs:us-east-1:111122223333:log-group:/aws/bedrock-agentcore/runtimes/act_teams_worker_2-*:*"]), OwnPeerMapAndCode = toset(["arn:aws:s3:::act-teams-code-111122223333/peers/worker-2.json", "arn:aws:s3:::act-teams-code-111122223333/code/agent.zip"]), ReadOpenRouterKey = toset(["arn:aws:secretsmanager:us-east-1:111122223333:secret:act-teams/openrouter-AbCdEf"]), ReadRunToken = toset(["arn:aws:secretsmanager:us-east-1:111122223333:secret:act-teams/run-token-GhIjKl"]), OwnWorkloadIdentityToken = toset(["arn:aws:bedrock-agentcore:us-east-1:111122223333:workload-identity-directory/default", "arn:aws:bedrock-agentcore:us-east-1:111122223333:workload-identity-directory/default/workload-identity/act_teams_worker_2-*"]) }
    error_message = "worker-2: a base-role statement has resources other than the reviewed ARNs (own logs, own peer map and the code zip, the OpenRouter secret, own workload identity)"
  }

  assert {
    condition     = { for s in data.aws_iam_policy_document.base["worker-3"].statement : s.sid => toset(s.resources) } == { OwnLogs = toset(["arn:aws:logs:us-east-1:111122223333:log-group:/aws/bedrock-agentcore/runtimes/act_teams_worker_3-*", "arn:aws:logs:us-east-1:111122223333:log-group:/aws/bedrock-agentcore/runtimes/act_teams_worker_3-*:*"]), OwnPeerMapAndCode = toset(["arn:aws:s3:::act-teams-code-111122223333/peers/worker-3.json", "arn:aws:s3:::act-teams-code-111122223333/code/agent.zip"]), ReadOpenRouterKey = toset(["arn:aws:secretsmanager:us-east-1:111122223333:secret:act-teams/openrouter-AbCdEf"]), ReadRunToken = toset(["arn:aws:secretsmanager:us-east-1:111122223333:secret:act-teams/run-token-GhIjKl"]), OwnWorkloadIdentityToken = toset(["arn:aws:bedrock-agentcore:us-east-1:111122223333:workload-identity-directory/default", "arn:aws:bedrock-agentcore:us-east-1:111122223333:workload-identity-directory/default/workload-identity/act_teams_worker_3-*"]) }
    error_message = "worker-3: a base-role statement has resources other than the reviewed ARNs (own logs, own peer map and the code zip, the OpenRouter secret, own workload identity)"
  }

  assert {
    condition     = { for s in data.aws_iam_policy_document.base["reviewer-1"].statement : s.sid => toset(s.resources) } == { OwnLogs = toset(["arn:aws:logs:us-east-1:111122223333:log-group:/aws/bedrock-agentcore/runtimes/act_teams_reviewer_1-*", "arn:aws:logs:us-east-1:111122223333:log-group:/aws/bedrock-agentcore/runtimes/act_teams_reviewer_1-*:*"]), OwnPeerMapAndCode = toset(["arn:aws:s3:::act-teams-code-111122223333/peers/reviewer-1.json", "arn:aws:s3:::act-teams-code-111122223333/code/agent.zip"]), ReadOpenRouterKey = toset(["arn:aws:secretsmanager:us-east-1:111122223333:secret:act-teams/openrouter-AbCdEf"]), ReadRunToken = toset(["arn:aws:secretsmanager:us-east-1:111122223333:secret:act-teams/run-token-GhIjKl"]), OwnWorkloadIdentityToken = toset(["arn:aws:bedrock-agentcore:us-east-1:111122223333:workload-identity-directory/default", "arn:aws:bedrock-agentcore:us-east-1:111122223333:workload-identity-directory/default/workload-identity/act_teams_reviewer_1-*"]) }
    error_message = "reviewer-1: a base-role statement has resources other than the reviewed ARNs (own logs, own peer map and the code zip, the OpenRouter secret, own workload identity)"
  }

  assert {
    condition     = { for s in data.aws_iam_policy_document.base["reviewer-2"].statement : s.sid => toset(s.resources) } == { OwnLogs = toset(["arn:aws:logs:us-east-1:111122223333:log-group:/aws/bedrock-agentcore/runtimes/act_teams_reviewer_2-*", "arn:aws:logs:us-east-1:111122223333:log-group:/aws/bedrock-agentcore/runtimes/act_teams_reviewer_2-*:*"]), OwnPeerMapAndCode = toset(["arn:aws:s3:::act-teams-code-111122223333/peers/reviewer-2.json", "arn:aws:s3:::act-teams-code-111122223333/code/agent.zip"]), ReadOpenRouterKey = toset(["arn:aws:secretsmanager:us-east-1:111122223333:secret:act-teams/openrouter-AbCdEf"]), ReadRunToken = toset(["arn:aws:secretsmanager:us-east-1:111122223333:secret:act-teams/run-token-GhIjKl"]), OwnWorkloadIdentityToken = toset(["arn:aws:bedrock-agentcore:us-east-1:111122223333:workload-identity-directory/default", "arn:aws:bedrock-agentcore:us-east-1:111122223333:workload-identity-directory/default/workload-identity/act_teams_reviewer_2-*"]) }
    error_message = "reviewer-2: a base-role statement has resources other than the reviewed ARNs (own logs, own peer map and the code zip, the OpenRouter secret, own workload identity)"
  }

  assert {
    condition     = { for s in data.aws_iam_policy_document.base["reviewer-3"].statement : s.sid => toset(s.resources) } == { OwnLogs = toset(["arn:aws:logs:us-east-1:111122223333:log-group:/aws/bedrock-agentcore/runtimes/act_teams_reviewer_3-*", "arn:aws:logs:us-east-1:111122223333:log-group:/aws/bedrock-agentcore/runtimes/act_teams_reviewer_3-*:*"]), OwnPeerMapAndCode = toset(["arn:aws:s3:::act-teams-code-111122223333/peers/reviewer-3.json", "arn:aws:s3:::act-teams-code-111122223333/code/agent.zip"]), ReadOpenRouterKey = toset(["arn:aws:secretsmanager:us-east-1:111122223333:secret:act-teams/openrouter-AbCdEf"]), ReadRunToken = toset(["arn:aws:secretsmanager:us-east-1:111122223333:secret:act-teams/run-token-GhIjKl"]), OwnWorkloadIdentityToken = toset(["arn:aws:bedrock-agentcore:us-east-1:111122223333:workload-identity-directory/default", "arn:aws:bedrock-agentcore:us-east-1:111122223333:workload-identity-directory/default/workload-identity/act_teams_reviewer_3-*"]) }
    error_message = "reviewer-3: a base-role statement has resources other than the reviewed ARNs (own logs, own peer map and the code zip, the OpenRouter secret, own workload identity)"
  }
}

# The callee check reads X-Act-Caller; a runtime forwards only allow-listed headers (AWS "Pass custom headers to AgentCore Runtime").
run "every_runtime_forwards_the_headers_the_app_reads" {
  command = apply


  assert {
    condition     = [for c in aws_bedrockagentcore_agent_runtime.agent["planner-1"].request_header_configuration : toset(c.request_header_allowlist)] == [toset(["X-Act-Caller", "X-Act-Token"])]
    error_message = "planner-1: the runtime must allow-list X-Act-Caller and X-Act-Token"
  }

  assert {
    condition     = [for c in aws_bedrockagentcore_agent_runtime.agent["planner-2"].request_header_configuration : toset(c.request_header_allowlist)] == [toset(["X-Act-Caller", "X-Act-Token"])]
    error_message = "planner-2: the runtime must allow-list X-Act-Caller and X-Act-Token"
  }

  assert {
    condition     = [for c in aws_bedrockagentcore_agent_runtime.agent["planner-3"].request_header_configuration : toset(c.request_header_allowlist)] == [toset(["X-Act-Caller", "X-Act-Token"])]
    error_message = "planner-3: the runtime must allow-list X-Act-Caller and X-Act-Token"
  }

  assert {
    condition     = [for c in aws_bedrockagentcore_agent_runtime.agent["worker-1"].request_header_configuration : toset(c.request_header_allowlist)] == [toset(["X-Act-Caller", "X-Act-Token"])]
    error_message = "worker-1: the runtime must allow-list X-Act-Caller and X-Act-Token"
  }

  assert {
    condition     = [for c in aws_bedrockagentcore_agent_runtime.agent["worker-2"].request_header_configuration : toset(c.request_header_allowlist)] == [toset(["X-Act-Caller", "X-Act-Token"])]
    error_message = "worker-2: the runtime must allow-list X-Act-Caller and X-Act-Token"
  }

  assert {
    condition     = [for c in aws_bedrockagentcore_agent_runtime.agent["worker-3"].request_header_configuration : toset(c.request_header_allowlist)] == [toset(["X-Act-Caller", "X-Act-Token"])]
    error_message = "worker-3: the runtime must allow-list X-Act-Caller and X-Act-Token"
  }

  assert {
    condition     = [for c in aws_bedrockagentcore_agent_runtime.agent["reviewer-1"].request_header_configuration : toset(c.request_header_allowlist)] == [toset(["X-Act-Caller", "X-Act-Token"])]
    error_message = "reviewer-1: the runtime must allow-list X-Act-Caller and X-Act-Token"
  }

  assert {
    condition     = [for c in aws_bedrockagentcore_agent_runtime.agent["reviewer-2"].request_header_configuration : toset(c.request_header_allowlist)] == [toset(["X-Act-Caller", "X-Act-Token"])]
    error_message = "reviewer-2: the runtime must allow-list X-Act-Caller and X-Act-Token"
  }

  assert {
    condition     = [for c in aws_bedrockagentcore_agent_runtime.agent["reviewer-3"].request_header_configuration : toset(c.request_header_allowlist)] == [toset(["X-Act-Caller", "X-Act-Token"])]
    error_message = "reviewer-3: the runtime must allow-list X-Act-Caller and X-Act-Token"
  }

}

# The run token: required at start, read from its secret (name only in the environment), never as a plain environment variable.
run "run_token_is_required_and_never_in_the_environment" {
  command = apply

  assert {
    condition     = aws_bedrockagentcore_agent_runtime.agent["planner-1"].environment_variables["ACT_REQUIRE_RUN_TOKEN"] == "true" && aws_bedrockagentcore_agent_runtime.agent["planner-1"].environment_variables["ACT_RUN_TOKEN_SECRET_ID"] == "act-teams/run-token" && !contains(keys(aws_bedrockagentcore_agent_runtime.agent["planner-1"].environment_variables), "ACT_RUN_TOKEN") && !anytrue([for k, v in aws_bedrockagentcore_agent_runtime.agent["planner-1"].environment_variables : v == random_password.run_token.result])
    error_message = "planner-1: the runtime must require the run token, name its secret and never carry the token value in its environment"
  }
  assert {
    condition     = aws_bedrockagentcore_agent_runtime.agent["planner-2"].environment_variables["ACT_REQUIRE_RUN_TOKEN"] == "true" && aws_bedrockagentcore_agent_runtime.agent["planner-2"].environment_variables["ACT_RUN_TOKEN_SECRET_ID"] == "act-teams/run-token" && !contains(keys(aws_bedrockagentcore_agent_runtime.agent["planner-2"].environment_variables), "ACT_RUN_TOKEN") && !anytrue([for k, v in aws_bedrockagentcore_agent_runtime.agent["planner-2"].environment_variables : v == random_password.run_token.result])
    error_message = "planner-2: the runtime must require the run token, name its secret and never carry the token value in its environment"
  }
  assert {
    condition     = aws_bedrockagentcore_agent_runtime.agent["planner-3"].environment_variables["ACT_REQUIRE_RUN_TOKEN"] == "true" && aws_bedrockagentcore_agent_runtime.agent["planner-3"].environment_variables["ACT_RUN_TOKEN_SECRET_ID"] == "act-teams/run-token" && !contains(keys(aws_bedrockagentcore_agent_runtime.agent["planner-3"].environment_variables), "ACT_RUN_TOKEN") && !anytrue([for k, v in aws_bedrockagentcore_agent_runtime.agent["planner-3"].environment_variables : v == random_password.run_token.result])
    error_message = "planner-3: the runtime must require the run token, name its secret and never carry the token value in its environment"
  }
  assert {
    condition     = aws_bedrockagentcore_agent_runtime.agent["worker-1"].environment_variables["ACT_REQUIRE_RUN_TOKEN"] == "true" && aws_bedrockagentcore_agent_runtime.agent["worker-1"].environment_variables["ACT_RUN_TOKEN_SECRET_ID"] == "act-teams/run-token" && !contains(keys(aws_bedrockagentcore_agent_runtime.agent["worker-1"].environment_variables), "ACT_RUN_TOKEN") && !anytrue([for k, v in aws_bedrockagentcore_agent_runtime.agent["worker-1"].environment_variables : v == random_password.run_token.result])
    error_message = "worker-1: the runtime must require the run token, name its secret and never carry the token value in its environment"
  }
  assert {
    condition     = aws_bedrockagentcore_agent_runtime.agent["worker-2"].environment_variables["ACT_REQUIRE_RUN_TOKEN"] == "true" && aws_bedrockagentcore_agent_runtime.agent["worker-2"].environment_variables["ACT_RUN_TOKEN_SECRET_ID"] == "act-teams/run-token" && !contains(keys(aws_bedrockagentcore_agent_runtime.agent["worker-2"].environment_variables), "ACT_RUN_TOKEN") && !anytrue([for k, v in aws_bedrockagentcore_agent_runtime.agent["worker-2"].environment_variables : v == random_password.run_token.result])
    error_message = "worker-2: the runtime must require the run token, name its secret and never carry the token value in its environment"
  }
  assert {
    condition     = aws_bedrockagentcore_agent_runtime.agent["worker-3"].environment_variables["ACT_REQUIRE_RUN_TOKEN"] == "true" && aws_bedrockagentcore_agent_runtime.agent["worker-3"].environment_variables["ACT_RUN_TOKEN_SECRET_ID"] == "act-teams/run-token" && !contains(keys(aws_bedrockagentcore_agent_runtime.agent["worker-3"].environment_variables), "ACT_RUN_TOKEN") && !anytrue([for k, v in aws_bedrockagentcore_agent_runtime.agent["worker-3"].environment_variables : v == random_password.run_token.result])
    error_message = "worker-3: the runtime must require the run token, name its secret and never carry the token value in its environment"
  }
  assert {
    condition     = aws_bedrockagentcore_agent_runtime.agent["reviewer-1"].environment_variables["ACT_REQUIRE_RUN_TOKEN"] == "true" && aws_bedrockagentcore_agent_runtime.agent["reviewer-1"].environment_variables["ACT_RUN_TOKEN_SECRET_ID"] == "act-teams/run-token" && !contains(keys(aws_bedrockagentcore_agent_runtime.agent["reviewer-1"].environment_variables), "ACT_RUN_TOKEN") && !anytrue([for k, v in aws_bedrockagentcore_agent_runtime.agent["reviewer-1"].environment_variables : v == random_password.run_token.result])
    error_message = "reviewer-1: the runtime must require the run token, name its secret and never carry the token value in its environment"
  }
  assert {
    condition     = aws_bedrockagentcore_agent_runtime.agent["reviewer-2"].environment_variables["ACT_REQUIRE_RUN_TOKEN"] == "true" && aws_bedrockagentcore_agent_runtime.agent["reviewer-2"].environment_variables["ACT_RUN_TOKEN_SECRET_ID"] == "act-teams/run-token" && !contains(keys(aws_bedrockagentcore_agent_runtime.agent["reviewer-2"].environment_variables), "ACT_RUN_TOKEN") && !anytrue([for k, v in aws_bedrockagentcore_agent_runtime.agent["reviewer-2"].environment_variables : v == random_password.run_token.result])
    error_message = "reviewer-2: the runtime must require the run token, name its secret and never carry the token value in its environment"
  }
  assert {
    condition     = aws_bedrockagentcore_agent_runtime.agent["reviewer-3"].environment_variables["ACT_REQUIRE_RUN_TOKEN"] == "true" && aws_bedrockagentcore_agent_runtime.agent["reviewer-3"].environment_variables["ACT_RUN_TOKEN_SECRET_ID"] == "act-teams/run-token" && !contains(keys(aws_bedrockagentcore_agent_runtime.agent["reviewer-3"].environment_variables), "ACT_RUN_TOKEN") && !anytrue([for k, v in aws_bedrockagentcore_agent_runtime.agent["reviewer-3"].environment_variables : v == random_password.run_token.result])
    error_message = "reviewer-3: the runtime must require the run token, name its secret and never carry the token value in its environment"
  }

  assert {
    condition     = aws_secretsmanager_secret_version.run_token.secret_string == random_password.run_token.result && aws_secretsmanager_secret.run_token.recovery_window_in_days == 0
    error_message = "the run-token secret must hold the generated token and be deleted at once on destroy"
  }
}
