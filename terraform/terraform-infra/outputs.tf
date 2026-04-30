output "ecr_repository_url" {
  value = aws_ecr_repository.focusboard_web.repository_url
}

output "cluster_name" {
  value = aws_eks_cluster.focusboard_cluster.name
}

output "cluster_endpoint" {
  value = aws_eks_cluster.focusboard_cluster.endpoint
}

output "node_group_name" {
  value = aws_eks_node_group.focusboard_nodes.node_group_name
}
output "aws_load_balancer_controller_role_arn" {
  description = "IAM Role ARN for AWS Load Balancer Controller"
  value       = aws_iam_role.aws_load_balancer_controller_role.arn
}

output "codebuild_role_arn" {
  description = "IAM Role ARN for CodeBuild"
  value       = aws_iam_role.codebuild_role.arn
}