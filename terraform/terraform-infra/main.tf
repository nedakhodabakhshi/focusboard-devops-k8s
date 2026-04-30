# Read the existing default VPC by its ID.
# This does not create a new VPC. It only fetches information about the selected VPC.
data "aws_vpc" "selected" {
  id = var.vpc_id
}

# Read the selected existing subnets by their IDs.
# These subnets will be used later by the EKS cluster and worker nodes.
data "aws_subnets" "selected" {
  filter {
    name   = "subnet-id"
    values = var.subnet_ids
  }
}

# Create an Amazon ECR repository for the FocusBoard web Docker image.
# This repository will store the application image used by EKS.
resource "aws_ecr_repository" "focusboard_web" {
  name                 = "focusboard-web"
  image_tag_mutability = "MUTABLE"

  # Enable vulnerability scanning whenever a new image is pushed.
  image_scanning_configuration {
    scan_on_push = true
  }

  # Add tags to organize AWS resources.
  tags = {
    Name    = "focusboard-ecr"
    Project = "focusboard"
  }
}

# Create an IAM role for the EKS control plane.
# This role will be assumed by the AWS EKS service, not by a human user.
resource "aws_iam_role" "eks_cluster_role" {
  name = "focusboard-eks-cluster-role"

  # Trust policy: allows the EKS service to assume this role.
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "eks.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })
}

# Attach the required AWS-managed policy to the EKS cluster role.
# This gives the EKS control plane permissions to manage cluster-related AWS resources.
resource "aws_iam_role_policy_attachment" "eks_cluster_policy" {
  role       = aws_iam_role.eks_cluster_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

# Create an IAM role for the EKS worker nodes.
# This role will be assumed by EC2 instances that become Kubernetes worker nodes.
resource "aws_iam_role" "eks_node_role" {
  name = "focusboard-eks-node-role"

  # Trust policy: allows EC2 instances to assume this role.
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })
}

# Attach the worker node policy.
# This allows worker nodes to join and communicate with the EKS cluster.
resource "aws_iam_role_policy_attachment" "node_policy_1" {
  role       = aws_iam_role.eks_node_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
}

# Attach the ECR read-only policy.
# This allows worker nodes to pull Docker images from Amazon ECR.
resource "aws_iam_role_policy_attachment" "node_policy_2" {
  role       = aws_iam_role.eks_node_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

# Attach the EKS CNI policy.
# This allows Kubernetes networking to work correctly inside the EKS cluster.
resource "aws_iam_role_policy_attachment" "node_policy_3" {
  role       = aws_iam_role.eks_node_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
}

# Create the EKS cluster control plane.
# This is the main Kubernetes cluster managed by AWS.
resource "aws_eks_cluster" "focusboard_cluster" {
  name     = "focusboard-eks-cluster"
  role_arn = aws_iam_role.eks_cluster_role.arn

  vpc_config {
    subnet_ids = var.subnet_ids
  }

  access_config {
    authentication_mode = "API_AND_CONFIG_MAP"
  }

  tags = {
    Name    = "focusboard-eks-cluster"
    Project = "focusboard"
  }
  # Make sure the EKS cluster role policy is attached before creating the cluster.
  depends_on = [
    aws_iam_role_policy_attachment.eks_cluster_policy
  ]
}


# Create a managed node group for the EKS cluster.
# These are the EC2 instances that will run Kubernetes pods.
resource "aws_eks_node_group" "focusboard_nodes" {
  cluster_name    = aws_eks_cluster.focusboard_cluster.name
  node_group_name = "focusboard-node-group"
  node_role_arn   = aws_iam_role.eks_node_role.arn

  # Use the selected subnets for the worker nodes.
  subnet_ids = var.subnet_ids

  # Configure scaling for the node group.
  scaling_config {
    desired_size = 2
    max_size     = 3
    min_size     = 2
  }

  # Instance type for worker nodes.
  # t3.medium is recommended to avoid resource issues.
  instance_types = ["t3.medium"]

  # Ensure IAM policies are attached before node group creation.
  depends_on = [
    aws_iam_role_policy_attachment.node_policy_1,
    aws_iam_role_policy_attachment.node_policy_2,
    aws_iam_role_policy_attachment.node_policy_3
  ]

  tags = {
    Name    = "focusboard-node-group"
    Project = "focusboard"
  }
}

# Manage the Amazon VPC CNI addon for the EKS cluster.
# This addon provides pod networking by assigning VPC IP addresses to Kubernetes pods.
resource "aws_eks_addon" "vpc_cni" {
  cluster_name = aws_eks_cluster.focusboard_cluster.name
  addon_name   = "vpc-cni"

  depends_on = [
    aws_eks_cluster.focusboard_cluster
  ]

  tags = {
    Name    = "focusboard-vpc-cni-addon"
    Project = "focusboard"
  }
}

# Manage the CoreDNS addon for the EKS cluster.
# CoreDNS provides internal DNS resolution for Kubernetes services and pods.
resource "aws_eks_addon" "coredns" {
  cluster_name = aws_eks_cluster.focusboard_cluster.name
  addon_name   = "coredns"

  depends_on = [
    aws_eks_node_group.focusboard_nodes
  ]

  tags = {
    Name    = "focusboard-coredns-addon"
    Project = "focusboard"
  }
}

# Manage the kube-proxy addon for the EKS cluster.
# kube-proxy handles Kubernetes Service networking and routes traffic to the correct pods.
resource "aws_eks_addon" "kube_proxy" {
  cluster_name = aws_eks_cluster.focusboard_cluster.name
  addon_name   = "kube-proxy"

  depends_on = [
    aws_eks_cluster.focusboard_cluster
  ]

  tags = {
    Name    = "focusboard-kube-proxy-addon"
    Project = "focusboard"
  }
}

# Create an access entry for the IAM user to access the EKS cluster.
# This replaces the old aws-auth ConfigMap method.
resource "aws_eks_access_entry" "admin_user" {
  cluster_name  = aws_eks_cluster.focusboard_cluster.name
  principal_arn = "arn:aws:iam::557690612191:user/cluser"
}

# Attach admin permissions to the IAM user for full cluster access.
resource "aws_eks_access_policy_association" "admin_user_policy" {
  cluster_name  = aws_eks_cluster.focusboard_cluster.name
  principal_arn = "arn:aws:iam::557690612191:user/cluser"

  policy_arn = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"

  access_scope {
    type = "cluster"
  }
}
# Read the TLS certificate from the EKS OIDC issuer.
# This is required to create the IAM OIDC provider for IRSA.
data "tls_certificate" "eks_oidc" {
  url = aws_eks_cluster.focusboard_cluster.identity[0].oidc[0].issuer
}

# Create the IAM OIDC provider for the EKS cluster.
# This allows Kubernetes service accounts to assume IAM roles securely.
resource "aws_iam_openid_connect_provider" "eks_oidc" {
  url = aws_eks_cluster.focusboard_cluster.identity[0].oidc[0].issuer

  client_id_list = [
    "sts.amazonaws.com"
  ]

  thumbprint_list = [
    data.tls_certificate.eks_oidc.certificates[0].sha1_fingerprint
  ]

  tags = {
    Name    = "focusboard-eks-oidc-provider"
    Project = "focusboard"
  }
}

# Create the IAM trust policy for the EBS CSI Driver service account.
# Only the ebs-csi-controller-sa service account in kube-system can assume this role.
data "aws_iam_policy_document" "ebs_csi_assume_role_policy" {
  statement {
    effect = "Allow"

    actions = [
      "sts:AssumeRoleWithWebIdentity"
    ]

    principals {
      type = "Federated"
      identifiers = [
        aws_iam_openid_connect_provider.eks_oidc.arn
      ]
    }

    condition {
      test     = "StringEquals"
      variable = "${replace(aws_eks_cluster.focusboard_cluster.identity[0].oidc[0].issuer, "https://", "")}:sub"
      values = [
        "system:serviceaccount:kube-system:ebs-csi-controller-sa"
      ]
    }

    condition {
      test     = "StringEquals"
      variable = "${replace(aws_eks_cluster.focusboard_cluster.identity[0].oidc[0].issuer, "https://", "")}:aud"
      values = [
        "sts.amazonaws.com"
      ]
    }
  }
}

# Create an IAM role for the Amazon EBS CSI Driver.
# The EBS CSI Driver uses this role to create and attach EBS volumes for Kubernetes PVCs.
resource "aws_iam_role" "ebs_csi_driver_role" {
  name               = "focusboard-ebs-csi-driver-role"
  assume_role_policy = data.aws_iam_policy_document.ebs_csi_assume_role_policy.json

  tags = {
    Name    = "focusboard-ebs-csi-driver-role"
    Project = "focusboard"
  }
}

# Attach the AWS-managed EBS CSI Driver policy to the role.
# This gives the driver permission to manage EBS volumes.
resource "aws_iam_role_policy_attachment" "ebs_csi_driver_policy" {
  role       = aws_iam_role.ebs_csi_driver_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
}

# Install the AWS EBS CSI Driver as an EKS managed add-on.
# This enables dynamic EBS volume provisioning for Kubernetes PVCs.
resource "aws_eks_addon" "ebs_csi_driver" {
  cluster_name             = aws_eks_cluster.focusboard_cluster.name
  addon_name               = "aws-ebs-csi-driver"
  service_account_role_arn = aws_iam_role.ebs_csi_driver_role.arn

  depends_on = [
    aws_iam_role_policy_attachment.ebs_csi_driver_policy
  ]

  tags = {
    Name    = "focusboard-ebs-csi-driver-addon"
    Project = "focusboard"
  }
}

# Create IAM policy for AWS Load Balancer Controller.
# This policy allows the controller to create and manage ALB, Target Groups, Listeners, and Security Group rules.
resource "aws_iam_policy" "aws_load_balancer_controller_policy" {
  name        = "focusboard-aws-load-balancer-controller-policy"
  description = "IAM policy for AWS Load Balancer Controller"
  policy      = file("${path.module}/aws-load-balancer-controller-policy.json")

  tags = {
    Name    = "focusboard-aws-load-balancer-controller-policy"
    Project = "focusboard"
  }
}

# Create IAM trust policy for AWS Load Balancer Controller service account.
# Only the aws-load-balancer-controller service account in kube-system can assume this role.
data "aws_iam_policy_document" "aws_load_balancer_controller_assume_role_policy" {
  statement {
    effect = "Allow"

    actions = [
      "sts:AssumeRoleWithWebIdentity"
    ]

    principals {
      type = "Federated"
      identifiers = [
        aws_iam_openid_connect_provider.eks_oidc.arn
      ]
    }

    condition {
      test     = "StringEquals"
      variable = "${replace(aws_eks_cluster.focusboard_cluster.identity[0].oidc[0].issuer, "https://", "")}:sub"
      values = [
        "system:serviceaccount:kube-system:aws-load-balancer-controller"
      ]
    }

    condition {
      test     = "StringEquals"
      variable = "${replace(aws_eks_cluster.focusboard_cluster.identity[0].oidc[0].issuer, "https://", "")}:aud"
      values = [
        "sts.amazonaws.com"
      ]
    }
  }
}

# Create IAM role for AWS Load Balancer Controller.
# The controller will use this role to call AWS APIs and create ALB resources.
resource "aws_iam_role" "aws_load_balancer_controller_role" {
  name               = "focusboard-aws-load-balancer-controller-role"
  assume_role_policy = data.aws_iam_policy_document.aws_load_balancer_controller_assume_role_policy.json

  tags = {
    Name    = "focusboard-aws-load-balancer-controller-role"
    Project = "focusboard"
  }
}

# Attach the Load Balancer Controller policy to the IAM role.
resource "aws_iam_role_policy_attachment" "aws_load_balancer_controller_policy_attachment" {
  role       = aws_iam_role.aws_load_balancer_controller_role.name
  policy_arn = aws_iam_policy.aws_load_balancer_controller_policy.arn
}

# IAM role for AWS CodeBuild.
# CodeBuild will use this role to build Docker images, push them to ECR,
# and deploy the application to EKS using Helm.
resource "aws_iam_role" "codebuild_role" {
  name = "focusboard-codebuild-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "codebuild.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })

  tags = {
    Name    = "focusboard-codebuild-role"
    Project = "focusboard"
  }
}

# IAM policy for CodeBuild.
# This allows CodeBuild to push Docker images to ECR,
# describe the EKS cluster, and write logs to CloudWatch.
resource "aws_iam_role_policy" "codebuild_policy" {
  name = "focusboard-codebuild-policy"
  role = aws_iam_role.codebuild_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ecr:GetAuthorizationToken",
          "ecr:BatchCheckLayerAvailability",
          "ecr:InitiateLayerUpload",
          "ecr:UploadLayerPart",
          "ecr:CompleteLayerUpload",
          "ecr:PutImage",
          "ecr:BatchGetImage",
          "ecr:DescribeRepositories"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "eks:DescribeCluster"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:GetObjectVersion",
          "s3:PutObject",
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.pipeline_bucket.arn,
          "${aws_s3_bucket.pipeline_bucket.arn}/*"
        ]
      }
    ]
  })
}

# Grant CodeBuild access to EKS cluster
resource "aws_eks_access_entry" "codebuild_access" {
  cluster_name  = aws_eks_cluster.focusboard_cluster.name
  principal_arn = aws_iam_role.codebuild_role.arn
  type          = "STANDARD"
}

# Attach admin policy to CodeBuild role for Kubernetes access
resource "aws_eks_access_policy_association" "codebuild_admin" {
  cluster_name  = aws_eks_cluster.focusboard_cluster.name
  principal_arn = aws_iam_role.codebuild_role.arn

  policy_arn = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"

  access_scope {
    type = "cluster"
  }
}

# CodeBuild project for building Docker image and deploying to EKS
resource "aws_codebuild_project" "focusboard_build" {
  name          = "focusboard-build"
  service_role  = aws_iam_role.codebuild_role.arn
  build_timeout = 30

  artifacts {
    type = "NO_ARTIFACTS"
  }

  environment {
    compute_type    = "BUILD_GENERAL1_SMALL"
    image           = "aws/codebuild/standard:7.0"
    type            = "LINUX_CONTAINER"
    privileged_mode = true # Required for Docker build
  }

  source {
    type            = "GITHUB"
    location        = "https://github.com/nedakhodabakhshi/focusboard-devops-k8s.git"
    buildspec       = "buildspec.yml"
    git_clone_depth = 1
  }

  logs_config {
    cloudwatch_logs {
      group_name  = "/aws/codebuild/focusboard"
      stream_name = "build-log"
    }
  }

  tags = {
    Name    = "focusboard-codebuild"
    Project = "focusboard"
  }
}

# IAM role for CodePipeline
resource "aws_iam_role" "codepipeline_role" {
  name = "focusboard-codepipeline-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "codepipeline.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })

  tags = {
    Name    = "focusboard-codepipeline-role"
    Project = "focusboard"
  }
}

# Policy for CodePipeline
resource "aws_iam_role_policy" "codepipeline_policy" {
  name = "focusboard-codepipeline-policy"
  role = aws_iam_role.codepipeline_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "codebuild:StartBuild",
          "codebuild:BatchGetBuilds"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "s3:*"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "codeconnections:UseConnection",
          "codestar-connections:UseConnection"
        ]
        Resource = "arn:aws:codeconnections:us-east-1:557690612191:connection/fb812773-431b-46ba-802b-20374f3f9ea7"
      }
    ]
  })
}

resource "aws_s3_bucket" "pipeline_bucket" {
  bucket = "focusboard-pipeline-bucket-557690612191"

  tags = {
    Name = "focusboard-pipeline-bucket"
  }
}
resource "aws_codepipeline" "focusboard_pipeline" {
  name     = "focusboard-pipeline"
  role_arn = aws_iam_role.codepipeline_role.arn

  artifact_store {
    location = aws_s3_bucket.pipeline_bucket.bucket
    type     = "S3"
  }

  stage {
    name = "Source"

    action {
      name             = "Source"
      category         = "Source"
      owner            = "AWS"
      provider         = "CodeStarSourceConnection"
      version          = "1"
      output_artifacts = ["source_output"]

      configuration = {
        ConnectionArn    = "arn:aws:codeconnections:us-east-1:557690612191:connection/fb812773-431b-46ba-802b-20374f3f9ea7"
        FullRepositoryId = "nedakhodabakhshi/focusboard-devops-k8s"
        BranchName       = "aws-eks-codepipeline"
      }
    }
  }

  stage {
    name = "Build"

    action {
      name             = "Build"
      category         = "Build"
      owner            = "AWS"
      provider         = "CodeBuild"
      input_artifacts  = ["source_output"]
      output_artifacts = ["build_output"]
      version          = "1"

      configuration = {
        ProjectName = aws_codebuild_project.focusboard_build.name
      }
    }
  }
}