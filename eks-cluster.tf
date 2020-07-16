
##Creating AWS Key Pair for EC2 Instance Login
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
locals{
        aws_query ={
                "query":"\"Reservations[*].Instances[?Tags[?Key=='eks:cluster-name'&&Value=='${var.eks_cluster_name}']&&State.Name=='running'].[PublicIpAddress]\""
        }
}
resource "null_resource" "worker_nodes_public_ip" {

        provisioner "local-exec" {
                command = "aws ec2 describe-instances  --query ${local.aws_query.query} --profile ${var.user_profile} --output text >${var.worker_node_ip_file_name} "
        }
        depends_on = [
                aws_eks_node_group.eks_node_group,
                aws_eks_node_group.eks_node_group_2,
        ]

}



## Enable EFS on Worker Nodes using Ansible Automation
resource "null_resource" "efs_enable_worker_nodes" {
        provisioner "local-exec" {
                command = "chmod 600 ${local_file.store_instance_key.filename} && ansible-playbook -i ${var.worker_node_ip_file_name} efs-software-install.yml -u ec2-user --private-key ${local_file.store_instance_key.filename} --ssh-extra-args='-o stricthostkeychecking=no'"
        }
        depends_on = [
                null_resource.worker_nodes_public_ip
        ]
}

