# Application Deployment using EKS and EFS
MERN Stack Application Deployment on Kuberenetes Cluster using Elastic Kubernetes Service. The persistence of the application and database pods is implemented using NFS server i.e Elastic File System. The EFS is used for multi-AZ pod deployment overcoming the constraints of Availability Zones in Elastic Block Storage.

<p align="center">
  <img src="/screenshots/infra_flow.jpg" width="950" title="Infrastructure Flow">
  <br>
  <em>Fig 1.: Project Flow Diagram </em>
</p>

By Default Terraform Kuberenetes provider uses host system `kubectl` config.

**Operating System** : Redhat Enterprise Linux 7 and above

### Software Pre-Requisites:
 - Ansible
 - Terraform
 - AWS CLI


