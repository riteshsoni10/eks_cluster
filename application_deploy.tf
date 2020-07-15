
## Persistent Volume for Application Pods
resource "kubernetes_persistent_volume_claim" "app_pvc" {

	metadata {
		name = "app-pvc"
		annotations = {
			"volume.beta.kubernetes.io/storage-class" = kubernetes_storage_class.efs_storage_class.id
		}
	}
	spec {
		resources {
			requests = {
				storage = var.app_storage
			}
		}
		access_modes = var.app_pvc_access_mode
	}
  depends_on = [
		kubernetes_storage_class.efs_storage_class
	]
}


locals {
	app_env_variables ={
        "DATABASE_USER": 
        "DATABASE_PASSWORD" : 
        "DATABASE_SERVER": 
        "DATABASE_PORT" :
        "DATABASE" :
	}
}

## Deployment Resource
resource "kubernetes_deployment" "app_deployment" {
	metadata {
		name = "app-deploy"
		labels = {
			app = "nodejs"
		}
	}
	spec{
		selector {
			match_labels = {
				app = "nodejs"
				tier = "frontend"
			}
		}
		strategy {
			type = "Recreate"
		}
		template {
			metadata {
				name = "app-pod"
				labels = {
					app = "nodejs"
					tier = "frontend"
				}
			}
			spec {
				container {
					name = "app-container"
					image = var.app_image_name
					dynamic "env" {
            for_each = local.app_env_variables
              content {
                name  = env.key
              	  value_from {
								    secret_key_ref {
									    name = kubernetes_secret.app_secret.metadata[0].name
									    key = env.value
								    }
							    }
            	  }
          		}				 
				  }
			}
		}
	}
  depends_on = [
		aws_eks_node_group.eks_node_group,
		aws_eks_node_group.eks_node_group_2,
		kubernetes_persistent_volume_claim.app_pvc,
		kubernetes_secret.app_secret,
	]
}



## Kubernetes Service resource for Database server

resource "kubernetes_service" "app_service" {
	metadata {
		name = "app-svc"
	}
	spec{
		selector = {
			app = kubernetes_deployment.app_deployment.spec[0].template[0].metadata[0].labels.app
			tier = kubernetes_deployment.app_deployment.spec[0].template[0].metadata[0].labels.tier
		}
		port {
			port = var.app_port
      target_port = var.app_container_port
		}
		type = "LoadBalancer"
	}
}
