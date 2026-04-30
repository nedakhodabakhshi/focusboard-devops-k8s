variable "aws_region" {
  default = "us-east-1"
}

variable "cluster_name" {
  default = "focusboard-eks-cluster"
}

variable "admin_user_arn" {
  default = "arn:aws:iam::557690612191:user/cluser"
}

variable "node_role_name" {
  default = "focusboard-eks-node-role"
}