variable "region" {
  description = "AWS region to deploy into."
  type        = string
  default     = "eu-west-2"
}

variable "cluster_name" {
  description = "EKS cluster name. Also used as the prefix for IAM roles and the Karpenter discovery tag."
  type        = string
  default     = "baseline"
}

variable "cluster_version" {
  description = "Kubernetes version. Keep within one minor of the latest EKS-supported release."
  type        = string
  default     = "1.30"
}

variable "vpc_cidr" {
  description = "Primary VPC CIDR. /16 gives you ~65k IPs — enough that you won't need the secondary-CIDR escape hatch until you're genuinely busy."
  type        = string
  default     = "10.0.0.0/16"
}

variable "availability_zones" {
  description = "AZs to spread subnets across. Three is the minimum for a quorum-friendly control plane and for cheap cross-AZ traffic patterns."
  type        = list(string)
  default     = ["eu-west-2a", "eu-west-2b", "eu-west-2c"]
}

variable "oidc_github_repo" {
  description = "GitHub `owner/repo` allowed to assume the Terraform CI role via OIDC. Must match the repo this Terraform runs from."
  type        = string
}
