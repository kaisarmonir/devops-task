environment        = "staging"
app_image          = "ghcr.io/kaisarmonir/devops-task:sha-c7a20b2"
log_retention_days = 7

# org SCP in this AWS account blocks IAM OIDC providers
github_oidc = false
