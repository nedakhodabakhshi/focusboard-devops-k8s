output "aws_auth_configmap_name" {
  description = "Name of aws-auth ConfigMap"
  value       = kubernetes_config_map_v1_data.aws_auth.metadata[0].name
}

output "cluster_name" {
  description = "EKS Cluster Name"
  value       = var.cluster_name
}

output "storage_class_name" {
  description = "StorageClass used for EBS-backed PVCs"
  value       = kubernetes_storage_class_v1.ebs_gp3.metadata[0].name
}