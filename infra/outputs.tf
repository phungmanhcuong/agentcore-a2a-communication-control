output "runtime_arns" {
  description = "agent name -> runtime ARN"
  value       = { for a, r in aws_bedrockagentcore_agent_runtime.agent : a => r.agent_runtime_arn }
}

output "entry_agents" {
  value = local.entry_agents
}

output "allowed_pairs" {
  description = "The expanded a2a.allow rules (caller, callee)."
  value       = local.pairs
}

output "secret_name" {
  description = "Set the value out of band: aws secretsmanager put-secret-value --secret-id <this> --secret-string file://<key file>"
  value       = aws_secretsmanager_secret.openrouter.name
}

output "run_token_secret_name" {
  description = "Callers outside the team (the operator's test script) read this secret and send its value as X-Act-Token: aws secretsmanager get-secret-value --secret-id <this> (needs GetSecretValue on it)"
  value       = aws_secretsmanager_secret.run_token.name
}
