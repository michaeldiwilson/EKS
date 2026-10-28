output "cluster_name" {
  description = "EKS cluster name. Feed into `aws eks update-kubeconfig --name ...`."
  value       = module.eks.cluster_name
}

output "cluster_endpoint" {
  description = "EKS API endpoint. Private — reachable from inside the VPC only."
  value       = module.eks.cluster_endpoint
}

output "cluster_oidc_issuer_url" {
  description = "Cluster OIDC issuer URL. Needed to add any extra IRSA roles outside this repo."
  value       = module.eks.cluster_oidc_issuer_url
}

output "vpc_id" {
  description = "VPC id. Needed by any peering, Transit Gateway, or endpoint config added later."
  value       = module.vpc.vpc_id
}
