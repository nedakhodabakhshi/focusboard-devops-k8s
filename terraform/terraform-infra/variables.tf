variable "aws_region" {
  default = "us-east-1"
}

variable "vpc_id" {
  default = "vpc-05b9fc4f0c956d7b8"
}

variable "subnet_ids" {
  default = [
    "subnet-03f8e36839a263ab8",
    "subnet-07d4bee4e0b3a37d7"
  ]
}