output "instance_id" {
  value = aws_instance.app.id
}

output "app_url" {
  value = "http://${aws_instance.app.public_ip}:${var.app_port}"
}

output "deploy_role_arn" {
  value = one(aws_iam_role.deploy[*].arn)
}

output "log_group" {
  value = aws_cloudwatch_log_group.app.name
}

output "deploy_user" {
  value = one(aws_iam_user.deploy[*].name)
}
