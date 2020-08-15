# Application Deployment using EKS and EFS
MERN Stack Application Deployment on Kuberenetes Cluster using Elastic Kubernetes Service. The persistence of the application and database pods is implemented using NFS server i.e Elastic File System. The EFS is used for multi-AZ pod deployment overcoming the constraints of Availability Zones in Elastic Block Storage.

<p align="center">
  <img src="/screenshots/infra_flow.jpg" width="950" title="Infrastructure Flow">
  <br>
  <em>Fig 1.: Project Flow Diagram </em>
</p>


**Operating System** : Redhat Enterprise Linux 7 and above

> Note:
>
>Since windows and linux have different escape expansion methods, would request you to run the scripts on Linux OS.

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

<p align="center">
  <img src="/screenshots/eks_iam_role.png" title="IAM Role">
  <br>
  <em>Fig 2.: EKS IAM Role </em>
</p>


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

<p align="center">
  <img src="/screenshots/eks_iam_role_policyattach.png" title="IAM Policy Attached">
  <br>
  <em>Fig 3.: EKS IAM Policy Attach </em>
</p>
	
	
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

<p align="center">
  <img src="/screenshots/terraform_apply_3.png" width="1000" title="EFS Enable">
  <br>
  <em>Fig 4.: EFS Enable on Worker Nodes </em>
</p>


**InstancePrivate Key**

The Private Key is genreated and attached to the node groups to enable remote access to the EKS cluster Worker nodes. The SSH key is used to remotely install needed softwares on worker nodes for EFS enable.

```
resource "aws_key_pair" "create_instance_key_pair"{
        key_name = "automation"
        public_key = tls_private_key.instance_key.public_key_openssh

		depends_on = [
			tls_private_key.instance_key
		]
}
```

<p align="center">
  <img src="/screenshots/worker_node_key_pair_plan.png" width="950" title="Terraform Plan">
  <br>
  <em>Fig 5.: Plan for Private Key </em>
</p>


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

We need to configure Ingress or Security group for the Elastic File System Service to allow EKS cluster worker nodes to mount the pods with the EFS filesystem.

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

<p align="center">
  <img src="/screenshots/efs_security_group_plan.png" title="EFS Security Group">
  <br>
  <em>Fig 6.: EFS Security Group </em>
</p>


## EFS-Provisioner

The Kubernetes does not have by-default support for EFS Storage Provisioner. We need to create custom Storage class to provision the peristent volumes for the kubernetes pods. S will be creating deployment resource in kubernetes  

*HCL Code* to create EFS-deployment resource is uploaded in repository with name **efs-provisioner.tf**.

We need to configure the parameter `automount_service_account_token` to *true*, since when the resource is launched using terraform code, the *service_accounts* are not mounted to the application pods. A **service account** provides an identity for processes that run in a Pod. It helps to assign special priviledges to the application Pods.

The `locals` block is used to define local variables in the code.

> Parameters
```
metadata              => The information about the Deployment Resource
spec.replicas         => The number of application pods to be managed using ReplicaSet
selector.match_labels => The value is used to monitor pods with same labels.
strategy              => To 
```

#### Deployment Strategies

The various different strategies are as follows:

**a. Recreate**

	Terminate the old version pods and release the pod with new version.
	
**b. Ramped**

	Release a new version of application pods on a rolling update fashion, one after the other
    
**c. Blue/Green** 

	Release a new version of application pods alongside the old version then switch traffic
    
**d. Canary** 

	Release a new version to a subset of users, then proceed to a full rollout
    
**e. A/B testing**

	Release a new version to a subset of users in a precise way (HTTP headers, cookie, weight, etc.). A/B testing
	is really a technique for making business decisions based on statistics but we will briefly describe the 
	process. This doesn’t come out of the box with Kubernetes, it implies extra work to setup a more advanced 
	infrastructure (Istio, Linkerd,	Traefik, custom nginx/haproxy, etc).


There are two types of **volume provisioning**  i.e *static* and *dynamic*. In `dynamic` volume provisioning `Persistent Volume Claim` requests the storage directly from the Storage Class. Since, we will be using EFS service for PVC, so we need to create custom storage class to provision volumes.

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

<p align="center">
  <img src="/screenshots/efs_storage_class_plan.png" title="EFS  Storage Class">
  <br>
  <em>Fig 7.: EFS Storage Class</em>
</p>


## Application Deployment 

In Application deployment we will be using 

- `Persistent Volume Claim` for data persistency even after the lifetime of the application pods. 
- `Service resource` type for internal and external connetivity of the applications
- `Secret resource` type to encode the credentials
- `Deployment` resource for fault tolerance of the aplication pods

### Persistent Volume Claim

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

<p align="center">
  <img src="/screenshots/mongo_pvc_plan.png" title="PVC Resource">
  <br>
  <em>Fig 8.: Mongo DB Persistent Volume </em>
</p>
								  
### Service Resource 

**Service Resource** in EKS Cluster creates the load balancer in Cluster based on the `type` parameter. There are three types of services. They are as follows:

**a. LoadBalancer**

	The EKS Cluster luanches the load balancer i.e Network,Application and Classic type load balancers.

**b. ClusterIP**

	The service created with this type will not be accessible from outside network, i.e; It will be connected 
	only from the worker nodes. Service name can be used for interaction between applications if ClusterIP is
	set to `None`.

**c. NodeIP**

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

<p align="center">
  <img src="/screenshots/mongo_service_plan.png" width="950" title="">
  <br>
  <em>Fig 9.: Kubernetes Service Resource </em>
</p>


### Secret Resource

Secret resource is used to encode the confidentials in kubernetes cluster. 

```
## Secret Resource for Database Pods
resource "kubernetes_secret" "mongo_secret" {
	metadata{
		name = "mongo-db-secret"
	}

	data = {
		root_username = "mongoadmin"
		root_password = "admin123"
		username = "appuser"
		password = "app1123"
		database = "nodejsdemo"
	}
  
}
```

<p align="center">
  <img src="/screenshots/mongo_secret_plan.png" title="Secret Resource">
  <br>
  <em>Fig 10.: Mongo DB Secret Resource </em>
</p>


### Deployment Resource

The deployment kubernetes resource is created to implement fault tolerance behaviour while running pods i.e, to restart the application pods in case anyone of them fails.



# Usage Instructions

You should have configured IAM profile in the controller node and all the pre-requisites. 

1. Clone this repository
2. Change the working directory to `automation-scripts`
3. Switch to the Admin or root user on controller node.
4. Run `terraform init`
5. Then, `terraform plan`, to see the list of resources that will be created

<p align="center">
  <img src="/screenshots/terraform_apply_1.png" width="950" title="Resources Progress ">
  <br>
  <em>Fig 11.: AWS Resources Progress </em>
</p>

<p align="center">
  <img src="/screenshots/terraform_apply_2.png" width="950" title="Resources Progress ">
  <br>
  <em>Fig 12.: AWS Resources Progress </em>
</p>

6. Then, `terraform apply -auto-approve`

<p align="center">
  <img src="/screenshots/terraform_apply.png" width="950" title="Resources Created ">
  <br>
  <em>Fig 13.: AWS Resources Created </em>
</p>

When you are done playing
```sh
terraform destroy -auto-approve
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
| worker_nodes_key_name | KeyName to SSH in Worker Nodes | string | `worker-nodes-key` | no |
| eks_node_group_name_1 | Name for the 1st Node Group | string | `` | yes |
| node_group_1_instance_types | Instance Types for Node Group 1 | list(string) | `["t2.small"]` | yes |
| eks_node_group_name_2 | Name for the 2st Node Group | string | `` | yes |
| node_group_2_instance_types | Instance Types for Node Group 2 | list(string) | `["t2.micro"]` | yes |
| worker_node_ip_file_name | Name of file to store Public IPs of worker nodes | string | `hosts` | no |
| mongo_db_port | Mongo Database Server Port | number | `27017`| yes |
| mongo_db_storage | Storage Requirement for Persitent Volume in Database server pod | string | `1Gi` | yes |
| efs_storage_provisioner_name | Provisioner Name | string | `aws-eks/efs` | no |
| mongo_db_pvc_access_mode | List of access modes (e.g. ReadWriteMany, ReadWriteOnce) | list(string) | `["ReadWriteMany"]` | yes |
| db_image_name | Docker image name for Database Server | string | `` | yes |
| mongo_volume_name | Mongo persistentvolume name | string | `mongo-persistent-vol` | no |
| mongo_data_directory | Data directory for Database Server | string | `/data/db` | yes |
| app_image_name | Docker image name for Application Server | string | `` | yes |
| app_port | Application Port for external Connectivity | number | `80` | yes |
| app_container_port | Port of Application running in Pod | number | `3000` | yes |

## Output

| Name | Description |
|------|-------------|
| vpc_cidr_block | VPC CIDR Block |
| subnet_ids | List of VPC Subnet Ids |
| efs_cluster_dns_name | EFS Cluster DNS Endpoint |
| efs_cluster_id | EFS Cluster File System Uninque Id |
| efs_security_group_id |Security Group Id attached to EFS Cluster|
| efs_storage_class_id | EFS Storage Class Id |
| eks_cluster_endpoint | Domain name Endpoint corresponding EKS Cluster |
| eks_cluster_role_arn | IAM Role ARN for EKS Cluster |
| node_group_arn | IAM Role ARN for Node Group|
| application_lb_end_point | Application Load Balancer Endpoint|

## Screenshots

**1. EFS Cluster**

<p align="center">
  <img src="/screenshots/aws_efs.png" width="950" title="AWS EFS">
  <br>
  <em>Fig 14.: AWS EFS Cluster </em>
</p>


**2. AWS EKS Cluster**

<p align="center">
  <img src="/screenshots/aws_eks_cluster.png" width="950" title="EKS Service">
  <br>
  <em>Fig 15.: AWS EKS Cluster</em>
</p>


**3. AWS EC2 Worker Nodes**

<p align="center">
  <img src="/screenshots/aws_efs.png" width="950" title="AWS EC2 Worker Nodes">
  <br>
  <em>Fig 16.: EKS Cluster Worker Nodes </em>
</p>


**4. Application Initial Welcome Page**

The application can be accessed using ELB Endpoint

<p align="center">
  <img src="screenshots/welcome_page.png" width="450" title="Welcome Page">
  <br>
  <em>Fig 17.: Application Welcome Page </em>
</p>


> **Source**: LinuxWorld Informatics Pvt Ltd. Jaipur
>
> **Under the Guidance of** : [Vimal Daga](https://in.linkedin.com/in/vimaldaga)
