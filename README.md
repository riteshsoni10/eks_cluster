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
aws ec2 describe-instances  --query \"Reservations[*].Instances[?Tags[?Key=='eks:cluster-name'&&Value=='${var.eks_cluster_name}']&&State.Name=='running'].[PublicIpAddress]\" --profile ${var.user_profile} --output text 
```

We will be storing the Public IPs in the `hosts` file to be used in ansible automation too install the softwares in the worker nodes.

```
ansible-playbook -i ${var.worker_node_ip_file_name} efs-software-install.yml -u ec2-user --private-key ${local_file.store_instance_key.filename} --ssh-extra-args='-o stricthostkeychecking=no
```







