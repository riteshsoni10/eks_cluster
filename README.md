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


