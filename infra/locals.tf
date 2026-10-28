data "aws_caller_identity" "current" {}

locals {
  team       = yamldecode(file(var.team_file))
  account_id = data.aws_caller_identity.current.account_id
  region     = local.team.region

  # roles -> agent names ("agents" entries are a name or {name: ...})
  roles = { for r, v in local.team.roles : r => [for a in v.agents : try(a.name, a)] }

  # agent name -> role
  agents = merge([for r, names in local.roles : { for n in names : n => r }]...)

  # AgentCore runtime names cannot contain a hyphen
  runtime_name = { for a in keys(local.agents) : a => "${var.runtime_prefix}_${replace(a, "-", "_")}" }

  # every selector used in a rule or in entry -> agent names ("role:x" expands, anything else is one agent)
  selectors = distinct(concat(
    [for r in local.team.a2a.allow : r["from"]],
    [for r in local.team.a2a.allow : r["to"]],
    try(local.team.a2a.entry, []),
  ))
  selector_agents = { for s in local.selectors : s => startswith(s, "role:") ? local.roles[substr(s, 5, -1)] : [s] }

  # the allow rules expanded to (caller, callee) pairs; deny by default means anything not listed here has no IAM statement
  pairs = distinct(flatten([
    for r in local.team.a2a.allow : [
      for s in local.selector_agents[r["from"]] : [
        for d in local.selector_agents[r["to"]] : { from = s, to = d } if s != d
      ]
    ]
  ]))

  peers   = { for a in keys(local.agents) : a => sort([for p in local.pairs : p.to if p.from == a]) }
  callers = { for a in keys(local.agents) : a => sort([for p in local.pairs : p.from if p.to == a]) }

  entry_agents = distinct(flatten([for s in try(local.team.a2a.entry, []) : local.selector_agents[s]]))
  auth_mode    = try(local.team.a2a.auth, "sigv4")

  bucket_name  = "${var.name_prefix}-code-${local.account_id}"
  boundary_arn = "arn:aws:iam::${local.account_id}:policy/${var.boundary_policy_name}"
  secret_name  = "${var.name_prefix}/openrouter"
  token_secret = "${var.name_prefix}/run-token"
  log_prefix   = "/aws/bedrock-agentcore/runtimes"
  # Headers the app reads (src/act_teams/a2a_client.py CALLER_HEADER, TOKEN_HEADER). A runtime forwards only allow-listed headers to the agent code;
  # without this list the callee check would see no caller and refuse every call with -32003 (HTTP 200). Names must not start with x-amz- or x-amzn-.
  request_headers = ["X-Act-Caller", "X-Act-Token"]
  ac_arn_base     = "arn:aws:bedrock-agentcore:${local.region}:${local.account_id}"
}

check "allow_rules_name_known_agents" {
  assert {
    condition     = alltrue([for p in local.pairs : contains(keys(local.agents), p.from) && contains(keys(local.agents), p.to)])
    error_message = "a2a.allow names an agent that is not in roles"
  }
}

check "entry_names_known_agents" {
  assert {
    condition     = alltrue([for e in local.entry_agents : contains(keys(local.agents), e)])
    error_message = "a2a.entry names an agent that is not in roles"
  }
}

check "auth_mode_is_known" {
  assert {
    condition     = contains(["none", "sigv4", "bearer"], local.auth_mode)
    error_message = "a2a.auth must be none, sigv4 or bearer"
  }
}
