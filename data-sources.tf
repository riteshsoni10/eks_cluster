data "aws_vpc" "vpc_details" {
  id = var.vpc_id
}

data "aws_eks_cluster_auth" "eks_cluster_token" {
  name = aws_eks_cluster.eks_cluster.id
}

data "aws_subnet_ids" "vpc_details" {
  vpc_id = var.vpc_id
}

data "aws_subnet" "eks_subnet" {
  for_each = data.aws_subnet_ids.vpc_details.ids
  id       = each.value
}
