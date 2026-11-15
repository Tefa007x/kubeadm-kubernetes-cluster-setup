#######################
## Terraform Outputs ##
#######################

output "master_public_ip" {
  value = aws_instance.master.public_ip
}

output "worker1_public_ip" {
  value = aws_instance.workers[0].public_ip
}

output "worker2_public_ip" {
  value = aws_instance.workers[1].public_ip
}

output "master_private_ip" {
  value = aws_instance.master.private_ip
}

output "worker1_private_ip" {
  value = aws_instance.workers[0].private_ip
}

output "worker2_private_ip" {
  value = aws_instance.workers[1].private_ip
}

output "ssh_command" {
  value = "ssh -i ${local.local_key_path} ubuntu@${aws_instance.master.public_ip}"
}
