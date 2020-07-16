output "efs_cluster_dns_name"{
	value= aws_efs_file_system.nfs_server.dns_name
}

output "efs_cluster_id"{
    value = aws_efs_file_system.nfs_server.id
}


output "efs_security_group_id"{
	value = aws_security_group.efs_security_group.id
}

output "efs_storage_class_id"{
	value = kubernetes_storage_class.efs_storage_class.id
}

output "vpc_cidr_block"{
	value = data.aws_vpc.vpc_details.cidr_block
}

output "subnet_ids"{
	value = data.aws_subnet_ids.vpc_subnet_details.ids
}

output "eks_cluster_endpoint" {
  value = aws_eks_cluster.eks_cluster.endpoint
}


output "eks_cluster_role_arn" {
    value = aws_iam_role.eks_role.arn
}

output "node_group_arn" {
    value = aws_iam_role.node_group_role.arn
}

output "application_lb_end_point" {
	value = kubernetes_service.app_service.load_balancer_ingress[0].hostname
}

