###################
## EC2 Instances ##
###################

data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"]

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

resource "aws_instance" "master" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type
  key_name               = aws_key_pair.generated_key.key_name
  subnet_id              = aws_subnet.public_1.id
  vpc_security_group_ids = [aws_security_group.k8s_sg.id]

  root_block_device {
    volume_size = 30
    volume_type = "gp3"
    delete_on_termination = true
  }

  tags = { 
    Name = "k8s-master" 
    }
}

resource "aws_instance" "workers" {
  count                  = 2  
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type
  key_name               = aws_key_pair.generated_key.key_name
  subnet_id              = aws_subnet.public_2.id
  vpc_security_group_ids = [aws_security_group.k8s_sg.id]

  root_block_device {
    volume_size = 20
    volume_type = "gp3"
    delete_on_termination = true
  }

  tags = { 
    Name = "k8s-worker-${count.index + 1}" 
    }
}

############################################################################
##  Auto-Generate Inventory.ini, Push Files & Run Playbook Inside Master  ##
############################################################################ 

locals {
    local_key_path = "~/.ssh/${var.my_key_pair}.pem"
}
# Enforces strict execution order by instructing Terraform to wait until both the master instance and the two workers instances 
# are provisioned and have their IP addresses assigned before running this block.

resource "terraform_data" "setup_master_ansible" {
  depends_on = [
    aws_instance.master,
    aws_instance.workers
  ]

# triggers_replace: By default, Terraform provisioners run only once during initial creation.
# This block tells Terraform to monitor the Private IP of the Master node and the Private IPs of the Worker nodes.
# If any instance is recreated and receives a new Private IP in the future,
# Terraform replaces this resource and re-runs the provisioners to update inventory.ini with the new IP addresses.

# join(",", aws_instance.workers[*].private_ip): Concatenates the list of worker Private IPs into a single comma-separated string 
# so Terraform can track them as a single state value.

  triggers_replace = [
    aws_instance.master.private_ip,
    join(",", aws_instance.workers[*].private_ip)
  ]

#This block defines how Terraform connects from your local machine to the k8s-master EC2 instance to execute the subsequent provisioners:
# type = "ssh": Specifies the SSH protocol.
# user = "ubuntu": The default administrative user on official Ubuntu AWS AMIs.
# private_key = file(local.local_key_path): Reads the raw content of your private SSH key from /home/tefa007/.ssh/EC2.key on your local machine for authentication.
# host = aws_instance.master.public_ip: Targets the auto-assigned Public IP of the Master node over the internet.

  connection {
    type        = "ssh"
    host        = aws_instance.master.public_ip
    user        = "ubuntu"
    private_key = file(local.local_key_path)
  }

# provisioner "file": Renders or uploads a file from your local environment directly onto the remote server (k8s-master).

# Terraform's file provisioner authenticates over SSH as the non-root ubuntu user, which does not have direct write permissions inside
# /etc/. Uploading inventory.ini and ansible.cfg to /tmp/ first avoids permission denied errors, 
# allowing the subsequent remote-exec step to move them into /etc/ansible/ using sudo.

#content = <<-EOT ... EOT: Dynamically interpolates the newly created EC2 Private IPs into an Ansible inventory string:
# k8s-master ansible_connection=local ...: Tells Ansible to execute tasks targeting k8s-master locally without opening an SSH session to itself, 
# since Ansible runs directly inside the Master node. It also stores private_ip as a host variable for /etc/hosts and kubeadm init.
# k8s-worker-1 ansible_host=...: Defines the connection endpoints for Worker 1 and Worker 2 using their internal VPC Private IPs (aws_instance.workers[0].private_ip and [1]).

# [k8s_cluster:children]: Groups both master and workers under a parent group called k8s_cluster 
# so Play 1 can apply common node prerequisites (containerd, kubeadm, sysctl) across all nodes simultaneously.

# [workers:vars]: Sets group-level variables for the worker nodes—specifying the ubuntu user, pointing to the uploaded SSH private key at /home/ubuntu/.ssh/EC2.key.pem, 
# and passing StrictHostKeyChecking=no to bypass interactive SSH host key prompts.

  provisioner "file" {
    destination = "/tmp/inventory.ini"
    content     = <<-EOT
      [master]
      k8s-master ansible_connection=local private_ip=${aws_instance.master.private_ip}

      [workers]
      k8s-worker-1 ansible_host=${aws_instance.workers[0].private_ip} private_ip=${aws_instance.workers[0].private_ip}
      k8s-worker-2 ansible_host=${aws_instance.workers[1].private_ip} private_ip=${aws_instance.workers[1].private_ip}

      [k8s_cluster:children]
      master
      workers

      [workers:vars]
      ansible_user=ubuntu
      ansible_ssh_private_key_file=/home/ubuntu/.ssh/${var.my_key_pair}.pem
      ansible_ssh_common_args='-o StrictHostKeyChecking=no'
    EOT
  }

# inventory = /etc/ansible/inventory.ini: Points Ansible globally to the system-wide inventory file so you can run ansible and ansible-playbook commands 
# from any directory without passing the -i flag.

# [privilege_escalation] (become = true, become_method = sudo, become_user = root, become_ask_pass = false): Configures Ansible to execute tasks and ad-hoc commands
# with root privileges (sudo) by default.Tasks in kubeadm_setup.yaml that explicitly declare become: false (such as cilium install,
# which reads /home/ubuntu/.kube/config as the ubuntu user) override this global setting and run safely as the non-root user.

# pipelining = True: Reduces the number of SSH operations required to execute modules on the worker nodes, speeding up playbook execution.

  provisioner "file" {
    destination = "/tmp/ansible.cfg"
    content     = <<-EOT
      [defaults]
      inventory = /etc/ansible/inventory.ini
      host_key_checking = False
      retry_files_enabled = False
      timeout = 30

      [privilege_escalation]
      become = true
      become_method = sudo
      become_user = root
      become_ask_pass = false

      [ssh_connection]
      pipelining = True
    EOT
  }

# First file block: Copies your private SSH key from your local machine to /tmp/${var.my_key_pair}.pem on the Master node, 
# enabling the Master to authenticate with the Worker nodes over SSH.

# Second file block: Uploads kubeadm_setup.yaml from your local Ansible directory (${path.module}) to /home/ubuntu/kubeadm_setup.yaml on the Master node.

  provisioner "file" {
        source      = local.local_key_path
        destination = "/tmp/${var.my_key_pair}.pem"
  }

  provisioner "file" {
    source      = "${path.module}/../ansible/kubeadm_setup.yaml"
    destination = "/home/ubuntu/kubeadm_setup.yaml"
  }

#Here, Terraform opens an SSH shell inside k8s-master and runs these commands sequentially:

# "set -e": Instructs the Bash shell to exit immediately with a non-zero status if any command fails, ensuring Terraform catches errors right away instead of continuing silently.

# "sudo mkdir -p /etc/ansible": Creates the system-wide /etc/ansible directory with root privileges before Ansible is even installed
# (-p ensures no error if the directory already exists).

# "sudo mv /tmp/inventory.ini /etc/ansible/inventory.ini" & "sudo mv /tmp/ansible.cfg /etc/ansible/ansible.cfg": 
# Moves both staged configuration files from /tmp/ into /etc/ansible/, where Ansible automatically detects them globally across the operating system.

# "chmod 400 /home/ubuntu/.ssh/${var.my_key_pair}.pem": Restricts permissions on the private key to read-only for the owner (ubuntu). 
# Without this, the SSH client rejects the key with an UNPROTECTED PRIVATE KEY FILE! error.

# "sudo apt-get update -y" & "sudo apt-get install -y ansible": Refreshes the Ubuntu package index and installs Ansible on the Master node.

# "ansible-galaxy collection install ansible.posix community.general": Installs the two Ansible collections required by kubeadm_setup.yaml 
# (ansible.posix.sysctl for kernel network parameters and community.general.modprobe for loading overlay and br_netfilter).

# "echo 'Waiting for worker nodes SSH to become ready...'": Prints a progress message to your terminal output during terraform apply.

# "ansible workers -m wait_for_connection -a 'timeout=180'": Prevents race conditions. Since the Master and Worker nodes boot concurrently, 
# the Master might finish installing Ansible before the Workers finish initializing their SSH daemons. 
# This command polls the Worker nodes (up to 180 seconds) until SSH responds before starting the playbook.

# "ansible-playbook /home/ubuntu/kubeadm_setup.yaml": Runs the playbook cleanly without extra CLI flags (-i or ANSIBLE_HOST_KEY_CHECKING=False),
# since host key checking, inventory paths, and privilege escalation are all handled automatically by /etc/ansible/ansible.cfg.

  provisioner "remote-exec" {
      inline = [
        "set -e",
        "sudo mkdir -p /etc/ansible",
        "sudo mv /tmp/inventory.ini /etc/ansible/inventory.ini",
        "sudo mv /tmp/ansible.cfg /etc/ansible/ansible.cfg",
        "sudo rm -f /home/ubuntu/.ssh/${var.my_key_pair}.pem",
        "sudo mv /tmp/${var.my_key_pair}.pem /home/ubuntu/.ssh/${var.my_key_pair}.pem",
        "chmod 400 /home/ubuntu/.ssh/${var.my_key_pair}.pem",
        "sudo apt-get update -y",
        "sudo apt-get install -y ansible",
        "ansible-galaxy collection install ansible.posix community.general",
        "echo 'Waiting for worker nodes SSH to become ready...'",
        "ansible workers -m wait_for_connection -a 'timeout=180'",
        "ansible-playbook /home/ubuntu/kubeadm_setup.yaml"
      ]
  }
}
