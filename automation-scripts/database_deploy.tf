
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
                                        port {
                                                name = "database-port"
                                                container_port =  var.mongo_db_port
                                        }
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
                                        volume_mount{
                                                name= var.mongo_volume_name
                                                mount_path= var.mongo_data_directory
                                        }
                                }
                                volume {
                                        name= var.mongo_volume_name
                                        persistent_volume_claim {
                                                claim_name= kubernetes_persistent_volume_claim.mongo_pvc.metadata[0].name
                                        }
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

