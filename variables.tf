variable "region_name"{
        type = string
        description = "Region Name to launch the Resoruces"
}

variable "user_profile" {
        type = string
        description = "AWS IAM User Profile to launch or configure resources"
}

variable "worker_node_ip_file_name"{
        type = string
        description = "file name to keep worker nodes Puublic IPs"
        default = "host"
}
variable "mongo_db_port"{
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