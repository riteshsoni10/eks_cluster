variable "region_name"{
        type = string
        description = "Region Name to launch the Resoruces"
}

variable "user_profile" {
        type = string
        description = "AWS IAM User Profile to launch or configure resources"
}


variable "eks_role_name" {
	type =  string
        description = "EKS Cluster Role Name"
}


variable "vpc_id" {
	type = string
        description = "VPC id for the EKS Cluster"
}

variable "eks_cluster_name" {
	type = string
        description = "Cluster Name"
	default = "eks-cluster"
}

variable "node_group_role_name" {
	type= string
        description = "Node Group role name"
}

variable "eks_node_group_name_1" {
	type = string
	description = "1st Node Group Name "
}


variable "eks_node_group_name_2" {
        type = string
	description = "1st Node Group Name "
}

variable "worker_node_ip_file_name" {
        type = string
        description = "file name to keep worker nodes Puublic IPs"
        default = "host"
}
variable "mongo_db_port" {
        type = number   
        description = "Mongo DB Server Port"
        default = 27017
}

variable "mongo_db_storage" {
        type = string
        description = " Mongo DB Server Persistent Volume Storage"
        default = "1Gi"
}

variable "efs_storage_provisioner_name" {
        type = string
        description = "Provisioner Name"
        default = "eks/aws-efs"
}

variable "mongo_db_pvc_access_mode" {
        type = list
        default = ["ReadWriteMany"]
}

variable "db_image_name" {
        type = string
        default = "riteshsoni296/mongo_server"
}

variable "mongo_volume_name" {
        type= string
        description = "Mongo persistentvolume name"
        default = "mongo-persistent-vol"
}

variable "mongo_data_directory"{
        type = string
        default = "/data/db"
}

variable "app_storage" {
        type = string
        description = " Application Server Persistent Volume Storage"
        default = "1Gi"
}

variable "app_pvc_access_mode" {
        type = list
        default = ["ReadWriteMany"]
}

variable "app_image_name" {
        type = string
        default = "riteshsoni296/nodejs_app:v1"
}


variable "app_port" {
        type = number
        default = 80
        description = "Port for external Connectivity"
}

variable "app_container_port" {
        type = number
        description = "Port of Application running in Pod"
        default = 3000
}


variable "app_volume_name" {
        type        = string
        description = "Node JS Application persistentvolume name"
        default     = "app-persistent-vol"
}

variable "app_data_directory"{
        type    = string
        default = "/usr/src/app"
}


variable "worker_nodes_key_name"{
        type = string
        description = "KeyName to SSH in Worker Nodes"
        default = "worker-nodes-key"
}

variable "node_group_1_instance_types" {
        type = list(string)
        description = "Instance Types for Node Group 1"
        default = ["t2.micro"]

}

variable "node_group_2_instance_types" {
        type = list(string)
        description = "Instance Types for Node Group 2"
        default = ["t2.small"]

}
