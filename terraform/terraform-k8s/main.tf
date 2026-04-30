# Read the IAM role used by the EKS worker nodes.
data "aws_iam_role" "eks_node_role" {
  name = var.node_role_name
}

# Manage the aws-auth ConfigMap inside the EKS cluster.
# This maps the EKS node role and admin IAM user into Kubernetes RBAC.
resource "kubernetes_config_map_v1_data" "aws_auth" {
  metadata {
    name      = "aws-auth"
    namespace = "kube-system"
  }

  data = {
    mapRoles = yamlencode([
      {
        rolearn  = data.aws_iam_role.eks_node_role.arn
        username = "system:node:{{EC2PrivateDNSName}}"
        groups = [
          "system:bootstrappers",
          "system:nodes"
        ]
      }
    ])

    mapUsers = yamlencode([
      {
        userarn  = var.admin_user_arn
        username = "admin"
        groups = [
          "system:masters"
        ]
      }
    ])
  }

  force = true
}

# Create a Kubernetes StorageClass for AWS EBS volumes.
# This StorageClass uses the EBS CSI Driver to dynamically create gp3 EBS volumes for PVCs.
resource "kubernetes_storage_class_v1" "ebs_gp3" {
  metadata {
    name = "ebs-gp3"
  }

  storage_provisioner = "ebs.csi.aws.com"

  reclaim_policy         = "Retain"
  volume_binding_mode    = "WaitForFirstConsumer"
  allow_volume_expansion = true

  parameters = {
    type      = "gp3"
    encrypted = "true"
  }
}