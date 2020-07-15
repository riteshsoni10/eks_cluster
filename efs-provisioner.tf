
## Enable EFS on Worker Nodes
resource "null_resource" "efs_enable_worker_nodes" {
        provisioner "local-exec" {
                command = "chmod 600 ${local_file.store_instance_key.filename} && ansible-playbook -i ${var.worker_node_ip_file_name} efs-software-install.yml -u ec2-user --private-key ${local_file.store_instance_key.filename} --ssh-extra-args='-o stricthostkeychecking=no'"
        }
        depends_on = [
                null_resource.worker_nodes_public_ip
        ]
}


## Security Group for EFS Cluster
resource "aws_security_group" "efs_security_group"{
	name = "allow_nfs_traffic"
	description = "Allow NFS Server Port Traffic from EKS Cluster"
	vpc_id = var.vpc_id

	ingress {
		description = "NFS Port"
		from_port = 2049
		to_port = 2049
		protocol = "tcp"
		cidr_blocks = [data.aws_vpc.vpc_details.cidr_block]
	}
	egress {
		from_port = 0
		to_port = 0
		protocol = "-1"
		cidr_blocks = ["0.0.0.0/0"]
	}
}


## EFS Cluster
resource "aws_efs_file_system" "nfs_server" {
  creation_token = "eks-efs-cluster"
  tags = {
    Name = "EKS_Cluster_NFS"
  }
}


## EFS Mount Target Subnets
resource "aws_efs_mount_target" "efs_mount_details"{
	count          = length( data.aws_subnet_ids.vpc_details.ids)
	file_system_id = aws_efs_file_system.nfs_server.id
	subnet_id       = tolist(data.aws_subnet_ids.vpc_details.ids)[count.index]
	security_groups = [aws_security_group.efs_security_group.id]
}


## EFS-Provisioner Namespace
resource "kubernetes_namespace" "efs_provisioner_namespace" {
  metadata {
    annotations = {
      name = "eks-efs-provisioner"
    }
    name = "eks-efs"
  }
}


##Service Account for EFS Provisioner
resource "kubernetes_service_account" "efs_provisioner_service_account" {
	metadata {
		name = "efs-sa"
		namespace = "eks-efs"
	}
  depends_on = [
		kubernetes_namespace.efs_provisioner_namespace
	]
}


## Cluster Role Binding for EFS Provisioner
resource "kubernetes_cluster_role_binding" "efs_provisioner_role_binding" {
	depends_on = [
		kubernetes_service_account.efs_provisioner_service_account
	]
	metadata {
		name = "nfs-provisioner-role-binding"
	}
	subject {
		kind = "ServiceAccount"
		name = "efs-sa"
		namespace = "eks-efs"
	}
	role_ref {
		kind = "ClusterRole"
		api_group = "rbac.authorization.k8s.io"
		name = "cluster-admin"
	}
}


## EFS Storage Class Custom Provisioner Deployment
locals {
	env_variables ={
		"FILE_SYSTEM_ID": aws_efs_mount_target.efs_mount_details[0].file_system_id
		"AWS_REGION" : var.region_name
		"PROVISIONER_NAME" : var.efs_storage_provisioner_name
	}
}

resource "kubernetes_deployment" "efs_provisioner_deployment" {
	depends_on = [
		aws_eks_node_group.eks_node_group,
		aws_eks_node_group.eks_node_group_2,
		kubernetes_cluster_role_binding.efs_provisioner_role_binding,
	]
	metadata {
		name = "efs-provisioner"
		namespace = "eks-efs"
	}
	spec {
		replicas = 1
		selector {
			match_labels = {
				app = "efs-provisioner"
			}
		}
		strategy {
			type = "Recreate"
		}
		template {
			metadata{
				labels = {
					app = "efs-provisioner"
				}
			}
			spec {
				service_account_name = "efs-sa"
				automount_service_account_token = true
				container {
					image = "quay.io/external_storage/efs-provisioner:v0.1.0"
					name = "efs-provisioner"
					dynamic "env" {
            for_each = local.env_variables
            content {
              name  = env.key
              value = env.value
            }
          }
					volume_mount {
						name = "pv-volume"
            mount_path = "/persistentvolumes"
					}
				}
				volume {
					name = "pv-volume"
					nfs {
						path = "/"
						server = aws_efs_mount_target.efs_mount_details[0].dns_name
					}
				}
			}
		}
	}
}


## EFS Storage Class
resource "kubernetes_storage_class" "efs_storage_class" {
	metadata {
		name = "aws-efs-sc"
	}
	storage_provisioner = var.efs_storage_provisioner_name
	parameters ={
		fsType = "xfs"
		type = "gp2"
	}
 	depends_on = [
		kubernetes_deployment.efs_provisioner_deployment
	]
}

