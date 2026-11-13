variable "environment" {
  type = string

  validation {
    condition     = contains(["staging", "production"], var.environment)
    error_message = "environment must be staging or production."
  }
}

variable "region" {
  type    = string
  default = "ap-southeast-2"
}

variable "instance_type" {
  type    = string
  default = "t3.micro"
}

variable "root_volume_size" {
  type    = number
  default = 10
}

variable "app_image" {
  description = "Image the instance runs on first boot, later changed by the deploy job"
  type        = string
}

variable "app_port" {
  type    = number
  default = 8080
}

variable "allowed_cidrs" {
  description = "Who can reach the app port"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "log_retention_days" {
  type    = number
  default = 14
}

variable "github_repo" {
  description = "owner/name of the repo allowed to deploy"
  type        = string
  default     = "kaisarmonir/devops-task"
}

variable "github_ref" {
  description = "Git ref allowed to assume the deploy role"
  type        = string
  default     = "refs/heads/main"
}
