locals {
  name      = "devops-task-${var.environment}"
  log_group = "/devops-task/${var.environment}/app"
}

data "aws_caller_identity" "current" {}

data "aws_vpc" "default" {
  default = true
}

# Amazon Linux 2023 comes with the SSM agent, so no SSH is needed
data "aws_ssm_parameter" "al2023" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

# Security group: app port in, HTTPS out (GHCR, Docker Hub, SSM, CloudWatch, dnf)

resource "aws_security_group" "app" {
  name        = local.name
  description = "devops-task app"
  vpc_id      = data.aws_vpc.default.id
}

resource "aws_vpc_security_group_ingress_rule" "app" {
  for_each          = toset(var.allowed_cidrs)
  security_group_id = aws_security_group.app.id
  description       = "app"
  cidr_ipv4         = each.value
  ip_protocol       = "tcp"
  from_port         = var.app_port
  to_port           = var.app_port
}

# SSH (for Ansible) and Grafana, only from admin IPs. Empty list = closed.
resource "aws_vpc_security_group_ingress_rule" "ssh" {
  for_each          = toset(var.admin_cidrs)
  security_group_id = aws_security_group.app.id
  description       = "ssh from admin"
  cidr_ipv4         = each.value
  ip_protocol       = "tcp"
  from_port         = 22
  to_port           = 22
}

resource "aws_vpc_security_group_ingress_rule" "grafana" {
  for_each          = toset(var.admin_cidrs)
  security_group_id = aws_security_group.app.id
  description       = "grafana from admin"
  cidr_ipv4         = each.value
  ip_protocol       = "tcp"
  from_port         = 3000
  to_port           = 3000
}

resource "aws_vpc_security_group_egress_rule" "https" {
  security_group_id = aws_security_group.app.id
  description       = "https out"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
}

# Logs

resource "aws_cloudwatch_log_group" "app" {
  name              = local.log_group
  retention_in_days = var.log_retention_days
}

# Instance role: SSM agent + writing to its own log group only

resource "aws_iam_role" "instance" {
  name = "${local.name}-instance"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.instance.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy" "logs" {
  name = "write-app-logs"
  role = aws_iam_role.instance.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["logs:CreateLogStream", "logs:PutLogEvents"]
      Resource = "${aws_cloudwatch_log_group.app.arn}:*"
    }]
  })
}

resource "aws_iam_instance_profile" "app" {
  name = local.name
  role = aws_iam_role.instance.name
}

# Instance

resource "aws_key_pair" "admin" {
  count      = var.ssh_public_key == "" ? 0 : 1
  key_name   = "${local.name}-admin"
  public_key = var.ssh_public_key
}

resource "aws_instance" "app" {
  ami                    = data.aws_ssm_parameter.al2023.value
  instance_type          = var.instance_type
  vpc_security_group_ids = [aws_security_group.app.id]
  iam_instance_profile   = aws_iam_instance_profile.app.name
  key_name               = one(aws_key_pair.admin[*].key_name)

  user_data = templatefile("${path.module}/user_data.sh.tftpl", {
    image     = var.app_image
    port      = var.app_port
    env       = var.environment
    region    = var.region
    log_group = aws_cloudwatch_log_group.app.name
  })
  user_data_replace_on_change = true

  metadata_options {
    http_tokens = "required"
  }

  root_block_device {
    volume_type = "gp3"
    volume_size = var.root_volume_size
    encrypted   = true
  }

  tags = {
    Name = local.name
  }

  # new AMI versions should not replace a running instance
  lifecycle {
    ignore_changes = [ami]
  }
}

# Deploy access for GitHub Actions: can only run shell commands on this
# one instance through SSM. Used by the OIDC role, or by an IAM user when
# the account does not allow OIDC providers (github_oidc = false).

locals {
  deploy_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = "ssm:SendCommand"
        Resource = [
          aws_instance.app.arn,
          "arn:aws:ssm:${var.region}::document/AWS-RunShellScript",
        ]
      },
      {
        Effect   = "Allow"
        Action   = ["ssm:GetCommandInvocation", "ssm:ListCommandInvocations"]
        Resource = "*"
      },
    ]
  })
}

resource "aws_iam_role" "deploy" {
  count = var.github_oidc ? 1 : 0
  name  = "${local.name}-deploy"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Federated = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:oidc-provider/token.actions.githubusercontent.com"
      }
      Action = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
          "token.actions.githubusercontent.com:sub" = "repo:${var.github_repo}:ref:${var.github_ref}"
        }
      }
    }]
  })
}

resource "aws_iam_role_policy" "deploy" {
  count  = var.github_oidc ? 1 : 0
  name   = "ssm-deploy"
  role   = aws_iam_role.deploy[0].id
  policy = local.deploy_policy
}

# Fallback: access key is created by hand (not in Terraform, so it is
# never stored in the state file) and kept in GitHub secrets.
resource "aws_iam_user" "deploy" {
  count = var.github_oidc ? 0 : 1
  name  = "${local.name}-deploy"
}

resource "aws_iam_user_policy" "deploy" {
  count  = var.github_oidc ? 0 : 1
  name   = "ssm-deploy"
  user   = aws_iam_user.deploy[0].name
  policy = local.deploy_policy
}
