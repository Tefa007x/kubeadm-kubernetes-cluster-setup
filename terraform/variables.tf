variable "aws_region" {
  description = "The AWS region"
  type        = string
  default     = "ca-central-1"
}

variable "aws_profile" {
  description = "The AWS profile to use"
  type        = string
}

variable "vpc_cidr" {
  description = "The CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "vpc_public_subnet_1" {
  description = "The CIDR block for the first public subnet"
  type        = string
  default     = "10.0.1.0/24"
}

variable "vpc_public_subnet_2" {
  description = "The CIDR block for the second public subnet"
  type        = string
  default     = "10.0.2.0/24"
}

variable "vpc_private_subnet_1" {
  description = "The CIDR block for the private subnet"
  type        = string
  default     = "10.0.3.0/24"
}

variable "my_cidr_ip" {
    description = "The CIDR block for my IP address to allow SSH access"
    type        = string
}

variable "my_key_pair" {
    description = "The name of the key pair to use for SSH access"
    type        = string
    default     = "EC2-key"
}

variable "instance_type" {
    description = "The instance type for the master node and worker nodes"
    type        = string
    default     = "c7i-flex.large"
}
