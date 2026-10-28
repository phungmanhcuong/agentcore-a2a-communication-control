variable "team_file" {
  description = "The one config file shared with the Python code."
  type        = string
  default     = "../team.yaml"
}

variable "code_zip_path" {
  description = "Direct-code deployment package built by scripts/build_zip.sh (linux arm64, Python 3.13)."
  type        = string
  default     = "../build/agent.zip"
}

variable "name_prefix" {
  description = "Prefix for IAM, S3 and Secrets Manager names (the grant allows act-teams-*)."
  type        = string
  default     = "act-teams"
}

variable "runtime_prefix" {
  description = "Prefix for AgentCore runtime names. Runtime names allow only letters, digits and underscores, so no hyphen."
  type        = string
  default     = "act_teams"
}

variable "boundary_policy_name" {
  description = "Permissions boundary that every IAM role must carry."
  type        = string
  default     = "act-teams-boundary"
}

variable "invoker_role_name" {
  description = "Role that starts tasks on the entry agents (the profile role used for tests)."
  type        = string
  default     = "act-teams-deployer"
}

variable "log_retention_days" {
  type    = number
  default = 7
}

variable "spend_cap_usd" {
  description = "Per-runtime-instance OpenRouter spend cap passed to the app."
  type        = number
  default     = 1
}
