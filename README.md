# Application Deployment using EKS and EFS
MERN Stack Application Deployment on Kuberenetes Cluster using Elastic Kubernetes Service. The persistence of the application and database pods is implemented using NFS server i.e Elastic File System. The EFS is used for multi-AZ pod deployment overcoming the constraints of Availability Zones in Elastic Block Storage.

<p align="center">
  <img src="/screenshots/infra_flow.jpg" width="950" title="Infrastructure Flow">
  <br>
  <em>Fig 1.: Project Flow Diagram </em>
</p>


**Operating System** : Redhat Enterprise Linux 7 and above

### Software Pre-Requisites:
 - Ansible
 - Terraform
 - AWS CLI

## Configuration of Providers

We need to configure terraform providers to interact with the Amazon Web Services and Kubernetes Cluster launched using Elastic Kubernetes Service.

1. AWS provider

  For aws provider configuration, we would require the `user_profile` and aws `region_name` where the kubernetes cluster will be launched.
  
```sh
## Provider AWS
provider "aws"{
	region = var.region_name
	profile = var.user_profile
}
```

2. Kubernetes provider

  We need to configure kubernetes credentials in the terraform code to interact with the kuberenetes cluster launched in Amazon Web Services.
  
```sh
## Provider Kubernetes
provider "kubernetes" {
	host                   = aws_eks_cluster.eks_cluster.endpoint
	cluster_ca_certificate = base64decode(aws_eks_cluster.eks_cluster.certificate_authority.0.data)
	token                  = data.aws_eks_cluster_auth.eks_cluster_token.token
	load_config_file       = false
	version                = "~> 1.9"
}
```

> Parameters

```
  host   => The API Endpoint of the EKS Cluster
  token => Authentication token for the Cluster
```

By Default Terraform Kuberenetes provider uses host system `kubectl` config. If `load_config_file` parameter is set to false, then the config file is not used to interact with the cluster.


## Elastic Kubernetes Service Cluster

In EKS Cluster, the master node is managed by Amazon Web Services. AWS provides High Availability, fault tolerance and Node Scaling for the master node. In EKS, we manage the worker nodes. The EKS launches worker nodes by utilising the Elastic Compute Service. The EKS Cluster needs permissions to monitor the cluster. So, we will be creating IAM role named `eks_role` and attach the required roles.

```sh
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
```

HCL code to attach required policies to the role

```sh
resource "aws_iam_role_policy_attachment" "AmazonEKSClusterPolicy" {
	policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
	role       = aws_iam_role.eks_role.name
}

resource "aws_iam_role_policy_attachment" "AmazonEKSServicePolicy" {
	policy_arn = "arn:aws:iam::aws:policy/AmazonEKSServicePolicy"
	role       = aws_iam_role.eks_role.name
}
```

HCL code to create EKS Cluster with input variables `eks_cluster_name`

```
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
```

> Parameters

```
  role_arn   => ARN of the role 
  subnet_ids => Subnet Ids for the worker nodes 
```



### Node Groups

In EKS Cluster, node groups are combination of all the instances or worker nodes with same configuration i.e instance type. There can be many node groups with the same worker node configurations. Internally, the number of worker nodes launched in the EKS Cluster are the autoscaling group instances. The HCL code to create the node groups in EKS 

```
## Node Group Creation
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
```

**Enable EFS Support on Worker Nodes**

We need to install software on all the worker nodes to enable high availability of persistent volumes used for Application deployment in Worker nodes. In EKS cluster worker nodes, the instances are tagged with Tag with `Name` : *eks:cluster-name* and `Value` : *cluster_name*. So we will be using AWS CLI to fetch Public IPS of all the instances or worker nodes with the tags to install the required packages using Ansible playbook.

```
aws ec2 describe-instances  --query \"Reservations[*].Instances[?Tags[?Key=='eks:cluster-name'\
&&Value=='${var.eks_cluster_name}']&&State.Name=='running'].[PublicIpAddress]\" --profile ${var.user_profile} --output text 
```

We will be storing the Public IPs in the `hosts` file to be used in ansible automation too install the softwares in the worker nodes.The playbook is present in the reposritory with name *efs-software-install.yml*.

```
ansible-playbook -i ${var.worker_node_ip_file_name} efs-software-install.yml -u ec2-user \
--private-key ${local_file.store_instance_key.filename} --ssh-extra-args='-o stricthostkeychecking=no
```

## Elastic File System

Elastic File System is file storage as Service provided by the Amazon Web Services. EFS works in a similiar way as Network File System. We will be creating EFS and allowing ingress traffic on TCP port 2049 i.e NFS Server port.


```
resource "aws_efs_file_system" "nfs_server" {
  creation_token = "eks-efs-cluster"
  tags = {
    Name = "EKS_Cluster_NFS"
  }
}
```

Ingress or Security group for the Elastic File System Service

```
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
```


## EFS-Provisioner

The Kubernetes does not have by-default support for EFS Storage Provisioner. We need to create custom Storage class to provision the peristent volumes for the kubernetes pods. S will be creating deployment resource in kubernetes  

HCL Code to create EFS-deployment resource

```
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
```

We would require to create our own custom storage class. There are two types of volume provisioning  i.e static and dynamic. In dynamic volume provisioning `Persistent Volume Claim` requests the storage directly from the Storage Class. 

```
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
```

## Application Deployment 

The Application deploymenent in EKS cluster. Persistent volume claim resource is created to make the data stored in the database pods permanent 

```
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
```


**Service Resource** in EKS Cluster creates the load balancer in Cluster based on the `type` parameter. There are three types of services. They are as follows:

a. LoadBalancer

	The EKS Cluster luanches the load balancer i.e Network,Application and Classic type load balancers.

b. ClusterIP

	The service created with this type will not be accessible from outside network, i.e; It will be connected 
	only from the worker nodes

c. NodeIP

	It is used for application external access from outside the woker nodes.
	
HCL Code to create service resource for internal connecctivity of database pod withn the application pod

```
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
```


## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|:----:|:-----:|:-----:|
| region_name | Default Region Name for Infrastructure | string | `` | yes |
| user_profile | IAM Credentials of AWS Account with required priviledges | string | `` | yes |
| vpc_id | VPC Id to launch the EKS Cluster | string | `` | yes |
| eks_role_name | Role Name  to be attached with EKS Cluster | string | `` | yes |
| eks_cluster_name | Name for EKS Cluster | string | `eks-cluster` | no |
| node_group_role_name | Role Name  to be attached with EKS Cluster Node group | string | `` | yes |
| eks_node_group_name_1 | Name for the 1st Node Group | string | `` | yes |
| eks_node_group_name_2 | Name for the 2st Node Group | string | `` | yes |
| worker_node_ip_file_name | Name of file to store Public IPs of worker nodes | string | `hosts` | no |
| mongo_db_port | Mongo Database Server Port | number | `27017`| yes |
| mongo_db_storage | Storage Requirement for Persitent Volume in Database server pod | string | `1Gi` | yes |
| efs_storage_provisioner_name | Provisioner Name | lstring | `aws-eks/efs` | no |
| mongo_db_pvc_access_mode | List of access modes (e.g. ReadWriteMany, ReadWriteOnce) | list(string) | `["ReadWriteMany"]` | yes |
| db_image_name | Docker image name for Database Server | string | `` | yes |
| mongo_volume_name | Mongo persistentvolume name | string | `mongo-persistent-vol` | no |
| mongo_data_directory | Data directory for Database Server | string | `/data/db` | yes |
| app_image_name | Docker image name for Application Server | string | `` | yes |
| app_port | Application Port for external Connectivity | number | `80` | yes |
| app_container_port | Port of Application running in Pod | number | `3000` | yes |
