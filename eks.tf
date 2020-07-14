

variable eks_role_name{
	type =  string
	default = "eks_cluster_role"
}


variable vpc_id{
	type = string
	default = "vpc-09889d55c39347616"
}

variable eks_cluster_name{
	type = string
	default = "eks-Cluster"
}

variable node_group_role_name{
	type= string
	default= "NodeGroup-Role"
}

variable eks_node_group_name_1 {
	type = string
	default = "ng_1"
}


variable eks_node_group_name_2 {
        type = string
        default = "ng_2"
}

data "aws_vpc" "vpc_details" {
  id = var.vpc_id
}

## Provider AWS
provider "aws"{
	region = var.region_name
	profile = var.user_profile
}

data "aws_eks_cluster_auth" "eks_cluster_token" {
  name = aws_eks_cluster.eks_cluster.id
}

## Provider Kubernetes
provider "kubernetes" {
	host                   = aws_eks_cluster.eks_cluster.endpoint
	cluster_ca_certificate = base64decode(aws_eks_cluster.eks_cluster.certificate_authority.0.data)
	token                  = data.aws_eks_cluster_auth.eks_cluster_token.token
	load_config_file       = false
	version                = "~> 1.9"
}

#Creating AWS Key Pair for EC2 Instance Login
resource "tls_private_key" "instance_key" {
	algorithm = "RSA"
}

resource "aws_key_pair" "create_instance_key_pair"{
        key_name = "automation"
        public_key = tls_private_key.instance_key.public_key_openssh

		depends_on = [
			tls_private_key.instance_key
		]
}

## Store Key in Controller instance
resource "local_file" "store_instance_key"{
	content = tls_private_key.instance_key.private_key_pem
	filename = "automation-key.pem"

	depends_on = [
		tls_private_key.instance_key
	]
}

resource "aws_iam_role" "eks_role" {
	name = var.eks_role_name
	assume_role_policy = jsonencode({
				Version = "2012-10-17"
  				Statement = [
   				{
    					Effect = "Allow"
    					Principal = {
    						Service = "eks.amazonaws.com"
    					}
    					Action = "sts:AssumeRole"
    				}]
			})

}

resource "aws_iam_role_policy_attachment" "AmazonEKSClusterPolicy" {
	policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
	role       = aws_iam_role.eks_role.name
}

resource "aws_iam_role_policy_attachment" "AmazonEKSServicePolicy" {
	policy_arn = "arn:aws:iam::aws:policy/AmazonEKSServicePolicy"
	role       = aws_iam_role.eks_role.name
}

data "aws_subnet_ids" "vpc_details" {
  vpc_id = var.vpc_id
}

data "aws_subnet" "eks_subnet" {
  for_each = data.aws_subnet_ids.vpc_details.ids
  id       = each.value
}


resource "aws_eks_cluster" "eks_cluster" {
  name     = var.eks_cluster_name
  role_arn = aws_iam_role.eks_role.arn

  vpc_config {
    subnet_ids = data.aws_subnet_ids.vpc_details.ids
  }

  depends_on = [
    aws_iam_role_policy_attachment.AmazonEKSClusterPolicy,
    aws_iam_role_policy_attachment.AmazonEKSServicePolicy,
  ]
}

resource "null_resource" "update_kube_config"{
        depends_on = [
                aws_eks_cluster.eks_cluster
        ]
        provisioner local-exec {
                command = "aws eks update-kubeconfig --name ${var.eks_cluster_name} --profile ${var.user_profile}"
        }
}

resource "aws_iam_role" "node_group_role" {
	name               = var.node_group_role_name
	assume_role_policy = jsonencode({
				Statement = [{
      				Action = "sts:AssumeRole"
      				Effect = "Allow"
      				Principal = {
        				Service = "ec2.amazonaws.com"
      				}
    				}]
    				Version = "2012-10-17"
  			    })
}

## Policies for EKS Node Group

resource "aws_iam_role_policy_attachment" "AmazonEKSWorkerNodePolicy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
  role       = aws_iam_role.node_group_role.name
}

resource "aws_iam_role_policy_attachment" "AmazonEKS_CNI_Policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
  role       = aws_iam_role.node_group_role.name
}

resource "aws_iam_role_policy_attachment" "AmazonEC2ContainerRegistryReadOnly" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  role       = aws_iam_role.node_group_role.name
}


#Node Group Creation

resource "aws_eks_node_group" "eks_node_group"{
	cluster_name = var.eks_cluster_name
	node_group_name = var.eks_node_group_name_1
	node_role_arn  = aws_iam_role.node_group_role.arn
	scaling_config {
		desired_size = 1
		min_size = 1
		max_size = 1
	}
	instance_types = ["t2.micro"]
	remote_access {
		ec2_ssh_key = aws_key_pair.create_instance_key_pair.key_name 
	}

	subnet_ids =  data.aws_subnet_ids.vpc_details.ids
	depends_on = [
			aws_eks_cluster.eks_cluster,
    		aws_iam_role_policy_attachment.AmazonEKSWorkerNodePolicy,
    		aws_iam_role_policy_attachment.AmazonEKS_CNI_Policy,
    		aws_iam_role_policy_attachment.AmazonEC2ContainerRegistryReadOnly,
  	]
}

resource "aws_eks_node_group" "eks_node_group_2"{
        cluster_name = var.eks_cluster_name
        node_group_name = var.eks_node_group_name_2
        node_role_arn  = aws_iam_role.node_group_role.arn
        scaling_config {
                desired_size = 1
		min_size     = 1
		max_size     = 1
        }
        instance_types = ["t2.small"]
        remote_access {
                ec2_ssh_key = aws_key_pair.create_instance_key_pair.key_name
        }

        subnet_ids = data.aws_subnet_ids.vpc_details.ids
        depends_on = [
				aws_eks_cluster.eks_cluster,
                aws_iam_role_policy_attachment.AmazonEKSWorkerNodePolicy,
                aws_iam_role_policy_attachment.AmazonEKS_CNI_Policy,
                aws_iam_role_policy_attachment.AmazonEC2ContainerRegistryReadOnly,
        ]
}


## Fetching Node_Group IPs
/*
locals{
	aws_query ={
		"query":"Reservations[*].Instances[?Tags[?Key=='eks:cluster-name'&&Value=='${var.eks_cluster_name}']&&State.Name=='running'].[PublicIpAddress]"
	}
}
resource "null_resource" "worker_nodes_public_ip" {
	
	provisioner "local-exec" {
		command = "aws ec2 describe-instances  --query \"${local.aws_query.query}\" --profile ${var.user_profile} --output text >${var.worker_node_ip_file_name}"
		#interpreter = ["PowerShell", "-Command"]
		/*
		aws ec2 describe-instances  --query "Reservations[*].Instances[?Tags[?Key=='eks:cluster-name'&&Value=='eks-Cluster']&&State.Name=='running'].[PublicIpAddress]" --profile aws_terraform_user  --output text
		
		aws ec2 describe-instances  --filters 'Name=tag:eks:cluster-name,Values=${var.eks_cluster_name}' 'Name=instance-state-name,Values=running' --query Reservations[*].Instances[*].[PublicIpAddress] --profile ${var.user_profile} --output text >${var.worker_node_ip_file_name}
		EOF
	#--filters 'Name=tag:eks:cluster-name,Values=${var.eks_cluster_name}' 'Name=instance-state-name, Values=running'
	
	}
	depends_on = [
		aws_eks_node_group.eks_node_group,
		aws_eks_node_group.eks_node_group_2,
	]
  
}
*/
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
	depends_on = [
		kubernetes_namespace.efs_provisioner_namespace
	]

	metadata {
		name = "efs-sa"
		namespace = "eks-efs"
	}
}
## Clutsr Role Binding for EFS Provisioner

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
	depends_on = [
		kubernetes_deployment.efs_provisioner_deployment
	]

	metadata {
		name = "aws-efs-sc"
	}
	storage_provisioner = var.efs_storage_provisioner_name
	parameters ={
		fsType = "xfs"
		type = "gp2"
	}
}


## Mongo_DB Server Pod

## Persistent Volume for Database Pods
resource "kubernetes_persistent_volume_claim" "mongo_pvc" {
	depends_on = [
		kubernetes_storage_class.efs_storage_class
	]
	metadata {
		name = "mongo-db-pvc"
		annotations = {
			"volume.beta.kubernetes.io/storage-class" = kubernetes_storage_class.efs_storage_class.id
		}
	}
	spec {
		resources {
			requests = {
				storage = var.mongo_db_storage
			}
		}
		access_modes = var.mongo_db_pvc_access_mode
	}
}


locals {
	mongo_db_env_variables ={
		"MONGO_INITDB_ROOT_USERNAME": "root_username"
		"MONGO_INITDB_ROOT_PASSWORD" : "root_password"
		"MONGO_INITDB_USERNAME" : "username"
		"MONGO_INITDB_PASSWORD" : "password"
		"MONGO_INITDB_DATABASE" : "database"
	}
}
## Deployment Resource
resource "kubernetes_deployment" "mongo_deployment" {
	depends_on = [
		aws_eks_node_group.eks_node_group,
		aws_eks_node_group.eks_node_group_2,
		kubernetes_persistent_volume_claim.mongo_pvc,
		kubernetes_secret.mongo_secret,
	]
	metadata {
		name = "mongo-db-deploy"
		labels = {
			app = "mongo_db"
		}
	}
	spec{
		selector {
			match_labels = {
				app = "database"
				tier = "backend"
			}
		}
		strategy {
			type = "Recreate"
		}
		template {
			metadata {
				name = "database-pod"
				labels = {
					app = "database"
					tier = "backend"
				}
			}
			spec {
				container {
					name = "db-container"
					image = var.db_image_name
					dynamic "env" {
            			for_each = local.mongo_db_env_variables
            			content {
              				name  = env.key
              				value_from {
								secret_key_ref {
									name = kubernetes_secret.mongo_secret.metadata[0].name
									key = env.value
								}
							}
            			}
          			}
					/*
					env_from {
						#prefix = "MONGO_INITDB_"
						secret_ref {
							name = kubernetes_secret.mongo_secret.metadata[0].name
						}
					}*/					 
				}
			}
		}
	}
}



## Kubernetes Service resource for Database server

resource "kubernetes_service" "monogo_service" {
	metadata {
		name = "mongo-db-svc"
	}
	spec{
		selector = {
			app = kubernetes_deployment.mongo_deployment.spec[0].template[0].metadata[0].labels.app
			tier = kubernetes_deployment.mongo_deployment.spec[0].template[0].metadata[0].labels.tier
		}
		port {
			port = var.mongo_db_port
		}
		cluster_ip = "None"
	}
}

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

