output "mongo_deployment"{
	value = kubernetes_deployment.mongo_deployment
}

output "mongo_secret" {
	value = kubernetes_secret.mongo_secret
} 

output "mongo_pvc"{
	value = kubernetes_persistent_volume_claim.mongo_pvc
}

output "mongo_svc"{
	value = kubernetes_service.monogo_service
}

output "efs_storage_class"{
	value = kubernetes_storage_class.efs_storage_class
}

output "efs_provisioner"{
	value = kubernetes_deployment.efs_provisioner_deployment
}

output "vpc_details"{
	value = data.aws_vpc.vpc_details
}

output "efs_security_group"{
	value = aws_security_group.efs_security_group
}

output "efs_mount_dns_name"{
  value=aws_efs_mount_target.efs_mount_details[0]
}

output "efs"{
	value= aws_efs_file_system.nfs_server
}

output "endpoint" {
  value = aws_eks_cluster.eks_cluster.endpoint
}

output "kubeconfig-certificate-authority-data" {
  value = aws_eks_cluster.eks_cluster.certificate_authority.0.data
}

output "eks_nodegroup"{
  value= aws_eks_node_group.eks_node_group_2
}

output "subnet_cidr_blocks" {
  value = [for s in data.aws_subnet.eks_subnet : s.cidr_block]
}

output "subnet_details" {
	value = data.aws_subnet.eks_subnet
}

output "vpc_id"{
	value = data.aws_subnet_ids.vpc_details
}

