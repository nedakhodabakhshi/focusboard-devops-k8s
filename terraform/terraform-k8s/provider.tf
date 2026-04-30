provider "aws" {
  region = var.aws_region
}

# Read the existing EKS cluster created by terraform-infra.
data "aws_eks_cluster" "focusboard" {
  name = var.cluster_name
}

# Configure the Kubernetes provider to connect to the EKS cluster.
provider "kubernetes" {
  host                   = data.aws_eks_cluster.focusboard.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.focusboard.certificate_authority[0].data)

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"

    args = [
      "eks",
      "get-token",
      "--cluster-name",
      var.cluster_name,
      "--region",
      var.aws_region
    ]
  }
}