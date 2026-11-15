#####################
##  VPC & Subnets  ##
#####################

resource "aws_vpc" "k8s_vpc" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags                 = {
    Name = "k8s-kubeadm-vpc"
  }
}

resource "aws_subnet" "public_1" {
  vpc_id                  = aws_vpc.k8s_vpc.id
  cidr_block              = var.vpc_public_subnet_1
  availability_zone       = "ca-central-1a"
  map_public_ip_on_launch = true

  tags                    = { 
    Name = "k8s-public-subnet-1-master" 
    }
}

resource "aws_subnet" "public_2" {
  vpc_id                  = aws_vpc.k8s_vpc.id
  cidr_block              = var.vpc_public_subnet_2
  availability_zone       = "ca-central-1b"
  map_public_ip_on_launch = true

  tags                    = { 
    Name = "k8s-public-subnet-2-workers" 
    }
}

resource "aws_subnet" "private_1" {
  vpc_id            = aws_vpc.k8s_vpc.id
  cidr_block        = var.vpc_private_subnet_1
  availability_zone = "ca-central-1d"

  tags              = { 
    Name = "k8s-private-subnet-db" 
    }
}

########################
##  Internet Gateway  ##
########################

resource "aws_internet_gateway" "k8s_igw" {
  vpc_id = aws_vpc.k8s_vpc.id

  tags   = {
    Name = "k8s-igw"
  }
} 

##################################
##  Route Tables & Associations ##
##################################

resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.k8s_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.k8s_igw.id
  }

  tags = { 
    Name = "k8s-public-rt" 
    }
}

resource "aws_route_table_association" "pub_1_assoc" {
  subnet_id      = aws_subnet.public_1.id
  route_table_id = aws_route_table.public_rt.id
}

resource "aws_route_table_association" "pub_2_assoc" {
  subnet_id      = aws_subnet.public_2.id
  route_table_id = aws_route_table.public_rt.id
}

resource "aws_route_table" "private_rt" {
  vpc_id = aws_vpc.k8s_vpc.id

  tags = { 
    Name = "k8s-private-rt" 
    }
}

resource "aws_route_table_association" "priv_1_assoc" {
  subnet_id      = aws_subnet.private_1.id
  route_table_id = aws_route_table.private_rt.id
}
