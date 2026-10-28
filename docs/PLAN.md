# PLAN: agent teams on Bedrock AgentCore (phase 1: plan, build, local tests)

This copy keeps only the A2A communication control parts of the plan. Section numbers are the original ones.

Written 2026-10-10 before any code. Every AWS statement below is quoted from official AWS documentation or the Terraform
provider documentation I opened on 2026-10-10 (sources at the end). Statements I could not verify are marked
**HYPOTHESIS** or **ASSUMPTION** and each has a phase-2 check. No AWS call was made in phase 1.

## 1. Goal and scope

| # | Request | Answer in this repo |
|---|---|---|
| 1 | AWS Bedrock AgentCore | One AgentCore Runtime per agent, protocol `A2A`, direct code deployment (zip) |
| 2 | Terraform for infra | `infra/`, AWS provider 6.68.0 (published 2026-10-07, has the AgentCore resources), Terraform 1.16.5 |
| 6 | A2A with allowed-from-config | section 2 |

Phase 1 (this task): plan, code, offline Terraform checks, local tests with real cheap models. Phase 2 (a second task): deploy
with profile `act-teams` in us-east-1, test, destroy. Cap: $15 AWS (phase 2) and a spend guard per ledger (one shared ledger per local run, code default $2; one ledger per runtime instance on AWS, `spend_cap_usd` default $1).

## 2. Point 6: the AWS feature for "A2A allowed from the config"

### 2.1 What the candidates really do (evidence)

| Candidate | What the documentation says | Governs agent-to-agent calls? |
|---|---|---|
| AgentCore Runtime A2A protocol | "Amazon Bedrock AgentCore's A2A protocol support enables seamless integration with A2A servers by acting as a transparent proxy layer ... JSON-RPC payloads from the InvokeAgentRuntime API are passed through directly to the A2A container without modification." Port 9000, path `/`, agent card at `/.well-known/agent-card.json` (S1). | It is the transport. It has no caller allow-list of its own. |
| IAM `bedrock-agentcore:InvokeAgentRuntime` | The authorization reference lists the action with resource types `runtime` and `runtime-endpoint` (S2). Resource-based policy doc: "For a request to be authorized ... The identity-based policies attached to the calling principal must allow the action on both the agent runtime and agent endpoint resources" (S5). | **Yes.** An identity policy on the caller scoped to the peers' ARNs is a per-caller allow-list; "Default Deny: If no policy explicitly permits an action, access is denied" (S5). |
| Resource-based policy on a runtime | "You can attach IAM-style policies directly to your resources to define rules around who can start runtime sessions ... (currently supported for Runtime, Gateway and Memory)". For SigV4: "Use specific AWS principals (IAM users, roles, or accounts) in the Principal element". The doc's own gateway example says: "add an explicit Deny for every other principal so that no other identity can invoke the runtime even with a permissive identity-based policy" (S5, S4). Terraform: `aws_bedrockagentcore_resource_policy` (S9). | **Yes, the callee side.** This is the second AWS layer. |
| AgentCore Identity inbound JWT authorizer | `allowedClients` (client_id claim), `allowedAudience` (aud), `allowedScopes`, custom claims. "An AgentCore Runtime can support either IAM SigV4 or JWT Bearer Token based inbound auth, but not both simultaneously." (S4) | Partly: allowed clients are per callee, but it needs an identity provider and per-agent client secrets. Heavier than IAM; kept as the swappable alternative (section 3). |
| AgentCore Policy (Cedar) and Gateway | "Policy in AgentCore intercepts all agent traffic through Amazon Bedrock AgentCore Gateways and evaluates each request against defined policies in the policy engine before allowing tool access." (S6) | **No for runtime-to-runtime A2A.** It governs tool calls that go through a Gateway. Not used. |
| AWS Agent Registry | "Discover and manage agents, tools, and resources" (S7): a catalog with curation and discovery. | No enforcement. Discovery only. Not used (the peer map comes from config). |

### 2.2 Chosen enforcement layers (deny by default at AWS and at the app)

| Layer | Mechanism | Default | Built in |
|---|---|---|---|
| AWS 1 (caller) | Execution role of agent X carries an inline policy `bedrock-agentcore:InvokeAgentRuntime` on the ARNs of exactly the peers `team.yaml` allows X to call | no statement means denied | `infra/iam.tf` |
| AWS 2 (callee) | `aws_bedrockagentcore_resource_policy` on each runtime: Allow the allowed callers' roles, plus explicit Deny to every principal not in that list (aws:PrincipalArn) | explicit deny | `infra/resource_policy.tf` |
| App 1 (caller) | the `ask_peer` tool is built only from the allowed peers; an unknown or disallowed peer raises before any network call | no tool, no call | `src/act_teams/a2a_client.py` |
| App 2 (callee) | A2A server middleware checks the `X-Act-Caller` claim against the allow rules; no header, no match = a JSON-RPC error -32003 in an HTTP 200 body (a 403 never reaches the caller on AgentCore, see docs/TESTING.md Phase 2 results). The runtime must forward that header, so every runtime carries `request_header_configuration { request_header_allowlist }` (section 2.3a) | JSON-RPC -32003 in HTTP 200 | `src/act_teams/server.py`, `infra/runtimes.tf` |

Run token (added after phase 2): all calls also carry `X-Act-Token`, a per-deployment secret generated by Terraform and read from Secrets Manager at start (`docs/TESTING.md`, "Run token wired for AWS"). It stops a caller outside the team (the account root user is not covered by AWS layer 2, confirmed in phase 2) from claiming a team name; it does not say which agent calls.

Honest limit of App 2: the caller name is a claim made by the caller, not an authenticated identity. On AWS the identity is
enforced by layers AWS 1 and 2 (SigV4 principal). App 2 stops misconfiguration and a prompt-injected agent that tries to
address a peer the code never wired, it does not stop a malicious process holding network access (locally there is no AWS layer).

### 2.3a Custom headers must be allow-listed (fix round 2026-10-10, M1)

Hypothesis from review: without an allowlist the runtime does not forward `X-Act-Caller`, so the callee check refuses every call with -32003 (HTTP 200 since the phase 2 fix; it answered 403 before).
Checked against S14 (opened 2026-10-10): "Configure the request header allowlist on your agent runtime so that custom headers are forwarded to
your agent code at invocation time". Rules from S14: a name is alphanumerics, hyphens and underscores; `x-amz-*` is not allowed; `x-amzn-*` is not
allowed except the prefix `X-Amzn-Bedrock-AgentCore-Runtime-Custom-`; at most 20 headers per runtime, 4 KB per value, names case-insensitive.
S14 also says "You can pass any valid HTTP header that is not in the restricted headers list", and the list (Authentication, Content, Caching,
Proxy, ...) has neither `X-Act-Caller` nor `X-Act-Token`. So **no prefix is required**: the names stay `X-Act-Caller` and `X-Act-Token`
(`src/act_teams/a2a_client.py` `CALLER_HEADER`, `TOKEN_HEADER`, the single source in Python). The API type allows 1 to 20 items, pattern
`[A-Za-z][A-Za-z0-9_-]{0,255}` (S15). Terraform argument: `request_header_configuration { request_header_allowlist = [...] }` (S8, provider v6.68.0,
file lines 179 and 347-351 of the raw doc, re-read 2026-10-10). Built: `infra/locals.tf` `request_headers`, `infra/runtimes.tf` on all runtimes.
UNTESTED: whether the A2A transparent proxy forwards allow-listed headers exactly like the HTTP protocol does (S14 shows the HTTP entrypoint);
see the phase-2 checks below.

### 2.3 One config drives everything

`team.yaml` is read by Python (`config.py`) and by Terraform (`yamldecode(file(...))`). `a2a.allow` has rules
`{from, to}` where each side is an agent name or `role:<role>`. Terraform expands them to per-agent peer lists; Python expands
them to the same lists; a unit test (`tests/test_policy.py`) pins both to the same table.

## 3. How one runtime authenticates to another

Chosen: **SigV4** with the caller's execution-role credentials. Quotes: "A2A servers support multiple authentication
mechanisms: OAuth 2.0 Bearer Tokens ... SigV4 Authentication: Standard AWS SigV4 authentication is also supported for
programmatic access." (S3). Inbound auth is IAM SigV4 by default; the runtime URL is
`https://bedrock-agentcore.<region>.amazonaws.com/runtimes/<url-encoded ARN>/invocations/` and every call carries the header
`X-Amzn-Bedrock-AgentCore-Runtime-Session-Id` (S1).

Why not JWT: it needs an identity provider (Cognito or other), a client per agent, and secrets to manage, which adds resources
and phase-2 cost without adding a stronger allow-list than IAM. The client is swappable anyway: `A2AAuth` is an interface
with `NoAuth` (local), `SigV4Auth` (AWS) and `BearerAuth` (JWT, token from a callable). `team.yaml` `a2a.auth` picks one;
a JWT deployment sets `authorizer_configuration` in Terraform (the provider supports `custom_jwt_authorizer`, S8).

## 6. Strands

Strands 1.59.0 provides `A2AServer` (`agent_factory` mode, FastAPI/Starlette app, agent card), `OpenAIModel` (client args
`base_url`, `params` passed to the chat completion call, which is how `extra_body={"provider": {"data_collection": "deny"}}`
is set), tools (`@tool`), and multi-agent `Swarm` and `Graph` which run in one process. Cross-runtime teamwork therefore uses
A2A peers, not Swarm: each agent gets an `ask_peer` tool. (Strands' own A2A client and vended `a2a_client` tool exist; I wrote
a thin JSON-RPC `message/send` client instead, because the auth must be swappable and the allow check must sit in front of it.)

## 7. Terraform

Provider `hashicorp/aws` 6.68.0 has `aws_bedrockagentcore_agent_runtime`, `..._agent_runtime_endpoint`,
`..._resource_policy`, `..._workload_identity` (S8, S9, provider repo tree 2026-10-10). Runtimes are `for_each` over agents.
Cycle avoidance: role (created first) -> runtime -> invoke policy and resource policy (they need peer runtime ARNs, so they are
separate resources). The peer map each agent reads at start (name -> runtime ARN, allowed peers only) is an S3 object written
after the runtimes, so runtime environment variables never reference other runtimes.

Constraints from the grant (task text): resources named `act-teams-*`; IAM roles only under path `/act-teams/` with the
permissions boundary `act-teams-boundary`; no Bedrock model invocation (models come from OpenRouter); us-east-1 only.
**ASSUMPTION A1:** AgentCore runtime names must match `[a-zA-Z][a-zA-Z0-9_]{0,47}` (S10, CreateAgentRuntime), so a runtime
cannot be called `act-teams-x`; I use `act_teams_<agent>` with underscores. If the IAM grant matches only `act-teams-*`
(hyphen), runtime creation will be denied: phase 2 step 1 is to create one runtime and read the error.
**ASSUMPTION A2:** the endpoint resource ARN is `.../runtime/<id>/runtime-endpoint/<name>` in the authorization reference but
`.../endpoint/<id>` in the resource-policy doc (S2, S5). Policies therefore use the runtime ARN and `<arn>/*`.

## 9. Test plan with must-fail controls

| Layer | Test | Must-fail control |
|---|---|---|
| config | schema, role/agent expansion, 3x3 and 3x10 | duplicate agent name, unknown role in a rule, rule to an unknown agent: each must be rejected |
| allow policy | allowed pairs pass | the same table with one rule removed must refuse that pair; empty `allow` refuses everything |
| spend guard | accumulates `usage.cost` from JSON and SSE | a cap below one call's cost must stop the next request |
| client | `ask_peer` only exists for allowed peers; headers; SigV4 signature shape | calling a disallowed peer raises before any socket opens (a socket-patching test proves no connection) |
| server | middleware: allowed caller reaches the handler, others get 200 + -32003 | spoofed caller for a pair that is not allowed gets -32003; no header gets -32003 |
| local multi-process | 9 real agents, real models: planner -> worker -> reviewer chain succeeds | worker -> planner refused (client) and a raw spoofed call refused (server) |
| Terraform (offline) | `fmt`, `validate`, `tflint`, `checkov` | a planted bad resource (open egress or an unscoped invoke `*`) must be flagged by checkov/our policy test |
| IAM expansion | per-agent invoke policy lists exactly the allowed peers | python mirror of the HCL expansion compared to `terraform console`-free golden table |

## Phase-2 checks (no code change now; each needs a deployed runtime, so each is UNTESTED today)

1. Does `aws:PrincipalArn` in the resource policy match roles under the path `/act-teams/` (the role ARN contains the path; the policy lists the full ARN with the path)? Test: a call from `planner-1` must be allowed and one from a role not listed must be denied.
2. Does A2A work with direct code deployment (zip, `PYTHON_3_13`)? S1 and S11 were read separately; the combination is an assumption.
3. A deployed call from `planner-1` (allowed to `reviewer-1` by the rule `planner-1 -> reviewer-1`) must succeed, and from `reviewer-1` (no rule to `planner-1`) must be refused by AWS (403 from the resource-policy Deny or the invoke policy), not only by the app.
4. Does the A2A proxy forward `X-Act-Caller` and `X-Act-Token` (section 2.3a)? Test: a call through the runtime URL must reach the callee check with the header.

## Sources (all opened 2026-10-10)

- S1 https://docs.aws.amazon.com/bedrock-agentcore/latest/devguide/runtime-a2a.html
- S2 https://servicereference.us-east-1.amazonaws.com/v1/bedrock-agentcore/bedrock-agentcore.json (actions, resource ARN formats)
- S3 https://docs.aws.amazon.com/bedrock-agentcore/latest/devguide/runtime-a2a-protocol-contract.html
- S4 https://docs.aws.amazon.com/bedrock-agentcore/latest/devguide/runtime-oauth.html
- S5 https://docs.aws.amazon.com/bedrock-agentcore/latest/devguide/resource-based-policies.html
- S6 https://docs.aws.amazon.com/bedrock-agentcore/latest/devguide/policy.html
- S7 https://docs.aws.amazon.com/bedrock-agentcore/latest/devguide/registry.html
- S8 https://raw.githubusercontent.com/hashicorp/terraform-provider-aws/main/website/docs/r/bedrockagentcore_agent_runtime.html.markdown (provider version 6.68.0 from https://registry.terraform.io/v1/providers/hashicorp/aws)
- S9 https://raw.githubusercontent.com/hashicorp/terraform-provider-aws/main/website/docs/r/bedrockagentcore_resource_policy.html.markdown
- S10 https://docs.aws.amazon.com/bedrock-agentcore-control/latest/APIReference/API_CodeConfiguration.html and API_CreateAgentRuntime.html
- S14 https://docs.aws.amazon.com/bedrock-agentcore/latest/devguide/runtime-header-allowlist.html (opened 2026-10-10)
- S15 https://docs.aws.amazon.com/bedrock-agentcore-control/latest/APIReference/API_RequestHeaderConfiguration.html (opened 2026-10-10)
