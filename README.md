# Automated AWS Kubeadm Cluster with Terraform, Ansible & Cilium

[![Terraform](https://img.shields.io/badge/Terraform-%3E%3D1.5-623CE4?logo=terraform&logoColor=white)](https://www.terraform.io/)
[![Ansible](https://img.shields.io/badge/Ansible-Automation-EE0000?logo=ansible&logoColor=white)](https://www.ansible.com/)
[![Kubernetes](https://img.shields.io/badge/Kubernetes-v1.31-326CE5?logo=kubernetes&logoColor=white)](https://kubernetes.io/)
[![Cilium](https://img.shields.io/badge/Cilium-eBPF_CNI-F8C517?logo=cilium&logoColor=black)](https://cilium.io/)
[![AWS](https://img.shields.io/badge/AWS-EC2_%26_VPC-FF9900?logo=amazonaws&logoColor=white)](https://aws.amazon.com/)

An end-to-end Infrastructure-as-Code (IaC) and configuration management solution to provision and bootstrap a **3-node Kubernetes cluster (1 Control Plane, 2 Workers)** on **`AWS EC2`** using **`Terraform`**, **`Ansible`**, **`kubeadm`**, **`containerd`**, and **`Cilium CNI`** in native eBPF `kube-proxy` replacement mode.

With a single command, the entire cluster is fully resilient, with isolated, non-overlapping network bootstrapped on modern **Compute Optimized `c7i-flex.large`** instances without manual intervention.

---

## 🏗️ AWS Kubernetes Cluster Architecture
To align with production readiness and lab reliability, this cluster uses a 2D architectural blueprint that matches the exact resources deployed by Terraform:

![AWS Kubernetes Cluster Architecture](/projects/kubeadm-setup/docs/images/Kubeadm_Cluster_Architecture.jpg)

---

## 🛠️ Deep Dive: Infrastructure As Code & Ansible Automation 

This repository relies on two powerful tools that work in synergy to orchestrate and deploy the infrastructure and software stack:

```text
+---------------------+                      +---------------------+
|      TERRAFORM      |                      |       ANSIBLE       |
|                     |                      |                     |
|   Provisions HW     |  ==================> |   System Updates    |
|  Generates Configs  |                      |   Install Runtime   |
|   Preps SSH/Hosts   |                      |   Bootstrap K8s     |
+---------------------+                      +---------------------+
```

### 1. Terraform Deployment (`terraform/`)
Terraform serves as the **Infrastructure-as-Code (IaC)** backbone. It communicates with AWS APIs to declaratively provision physical and networking virtual hardware. 
* **VPC & Subnets:** Deploys a custom VPC (`10.0.0.0/16`) featuring non-overlapping subnets (`10.0.1.0/24`, `10.0.2.0/24`, `10.0.3.0/24`) to handle secure internal network routing.
* **Security Groups:** Enforces granular firewalls, allowing open SSH (`port 22`) with your `local IP Address` for operations and full intra-cluster communication on `10.0.0.0/16` while keeping everything closed to external threats.
* **EC2 Compute Nodes:** Provisions **3x `c7i-flex.large`** instances (Ubuntu 24.04 LTS) with optimized GP3 EBS storage.
* **Configuration Bridging:** Automatically writes the local Ansible `inventory.ini` and `ansible.cfg` directly on the `k8s-master`, passing on dynamic network data like private IP variables without manual handoffs.

### 2. Ansible Orchestration (`ansible/kubeadm_setup.yaml`)
Ansible takes the lead for **Configuration Management & Automation**. Working on the newly minted EC2 nodes, this playbook execute the multi-tiered configuration to deploy the nodes as a unified Cluster:
* **Host Preparation:** Updates Ubuntu, loads kernel modules (such as `overlay`, `br_netfilter`), adjusts sysctl network tuning, and disables SWAP on all nodes (an absolute requirement for Kubelet stability).
* **Container Runtime Setup:** Installs `containerd` and sets up Cgroups, allowing fast, standardized container process Isolation.
* **Kubernetes Packages:** Installs critical components (`kubelet`, `kubeadm`, `kubectl`) locked to a consistent target version.
* **Secure Master Bootstrap:** Runs `kubeadm init` on the `k8s-master` Node using `10.244.0.0/16` for Pod networks, prevents network routes from overlapping with AWS IP allocation, and captures secure tokens.
* **Auto Worker Joining:** Fetches dynamic cluster join keys and registers the two Workers (`k8s-worker-1` & `k8s-worker-2`) as fully integrated compute nodes.
* **Kube-Proxy-Free Cilium Deployment:** Installs Cilium CNI on top of eBPF. Eliminating `kube-proxy` allows container-to-container traffic to skip traditional IPTables processing for lightning-fast network speeds.

---

## 📂 Repository Structure

```text
.
├── ansible/
│   └── kubeadm_setup.yaml    # Comprehensive Ansible Playbook for cluster bootstrap
├── terraform/
│   ├── main.tf               # EC2s (c7i-flex.large), and Ansible Configuration
│   ├── network.tf            # AWS VPC, Subnet definitions and route tables
│   ├── security.tf           # Security group ingress/egress rules and key pair
│   ├── variables.tf          # Terraform input variables
│   ├── outputs.tf            # Outputs (Master Public IP & Private IP, Workers Public IPs & Private IPs and SSH command to master instance)
│   └── provider.tf           # AWS provider configuration
├── README.md                 # Project documentation
└── .gitignore                # Uncommited files 
```

---

## 📋 Prerequisites

1. **[Terraform](https://developer.hashicorp.com/terraform/install)** `1.17.2 (latest)` installed on your local workstation.
2. **AWS CLI** configured with your AWS profile.
3. **AWS EC2 Key Pair:**
   * your `Key Pair` registered in AWS EC2 (`ca-central-1 region`).
   * The private key stored locally at `~/.ssh/`.

---

## 🚀 Quick Start (One-Command For Setup)

### 1. Clone the Repository
```bash
git clone https://github.com/Tefa007x/kubeadm-kubernetes-cluster-setup.git
cd kubeadm-kubernetes-cluster-setup/terraform
```

### 2. Initialize and Apply Terraform
```bash
terraform init
terraform validate
terraform apply -auto-approve
```

---

## 🌐 AWS Infrastructure Verification

After applying Terraform, verify your AWS console to ensure the resources were successfully created.

### Running EC2 Instances (`c7i-flex.large`):
Verify that the `k8s-master`, `k8s-worker-1`, and `k8s-worker-2` instances are up and `Running` in AWS.

![AWS EC2 Instances Running](/projects/kubeadm-setup/docs/images/EC2_Instances.png) 

### Deployed VPC & Subnet Resources:
Ensure the custom VPC `k8s-kubeadm-vpc` is created with its corresponding public and private subnets.

![AWS Deployed VPC](/projects/kubeadm-setup/docs/images/VPC.png) 

---

## 🔍 Validate Cluster Health

After connecting to the `k8s-master` using SSH `(terraform output ssh_command)`, run the following commands to confirm that the entire cluster's health is validated:

### 1. Validate Nodes and Runtime
Confirm that all 3 nodes have successfully joined the cluster and transitioned into the `Ready` status:
```bash
kubectl get nodes -o wide
```
![kubectl get nodes](/projects/kubeadm-setup/docs/images/Nodes_Validation.png) 

### 2. Validate Cilium Networking
Check the deployment health of Cilium daemonsets and confirm eBPF connectivity is running normally:
```bash
cilium status --wait 
```
![cilium status](/projects/kubeadm-setup/docs/images/Cilium_Status.png)

### 3. Valitade System Pods
Ensure that all `kube-system` pods are healthy and running normally 
```bash
kubectl get pods -n kube-system -o wide
```
![kube-system](/projects/kubeadm-setup/docs/images/Kube_System.png)

### 4. Check Network Interface Connection (Ping)
Validate network-to-network reachability and connectivity across the workers using ansible connectivity pings:
```bash
ansible all -m ping
```
![ansible ping](/projects/kubeadm-setup/docs/images/Ansible_ping.png)

### 5. Test Kubelet Host Routing
Check `ping` between Master and Workers to ensure connectivity (From `master` node):
```bash
ping k8s-worker-1
ping k8s-worker-2
```
![workers ping](/projects/kubeadm-setup/docs/images/Workers_Ping.png)

---

## 🧹 Cleanup

To safely destroy all AWS EC2 instances, subnets, and VPC resources:

```bash
terraform destroy -auto-approve
```
