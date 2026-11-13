environment        = "staging"
app_image          = "ghcr.io/kaisarmonir/devops-task:sha-c7a20b2"
log_retention_days = 7

# monitoring stack runs here too (Ansible), 1GB of t3.micro is not enough
instance_type    = "t3.small"
root_volume_size = 20

# test env, other people review the dashboards
grafana_cidrs = ["0.0.0.0/0"]

# org SCP in this AWS account blocks IAM OIDC providers
github_oidc = false
