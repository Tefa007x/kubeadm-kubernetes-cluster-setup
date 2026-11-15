####################
## Security Group ##
####################

resource "aws_security_group" "k8s_sg" {
  name        = "k8s-cluster-sg"
  description = "Allow SSH, full intra-cluster traffic, and outbound internet"
  vpc_id      = aws_vpc.k8s_vpc.id


  ingress {
    description = "SSH access to the cluster"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.my_cidr_ip]
  }



  
  ingress {
    description = "Allow all traffic between cluster nodes (API Server, etcd, kubelet, Cilium)"
    from_port = 0
    to_port   = 0
    protocol  = "-1"
    cidr_blocks = [var.vpc_cidr]
    self      = true
  }

  
  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { 
    Name = "k8s-cluster-sg" 
    }
}

################
##  Key Pair  ##
################

data "tls_public_key" "ssh_key" {
  private_key_pem = file(local.local_key_path)
}

resource "aws_key_pair" "generated_key" {
  key_name   = var.my_key_pair
  public_key = data.tls_public_key.ssh_key.public_key_openssh
}