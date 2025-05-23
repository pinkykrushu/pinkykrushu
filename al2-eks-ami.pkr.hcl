packer {
  required_plugins {
    amazon = {
      version = ">= 1.2.6"
      source  = "github.com/hashicorp/amazon"
    }
  }
}

variable "aws_region" {
  type    = string
  default = "us-west-2"
}

variable "instance_type" {
  type    = string
  default = "t3.medium"
}

variable "eks_version" {
  type    = string
  default = "1.28"  # Update as needed
}

source "amazon-ebs" "al2" {
  region        = var.aws_region
  instance_type = var.instance_type
  ami_name      = "eks-node-al2-${var.eks_version}-{{timestamp}}"
  
  source_ami_filter {
    filters = {
      name                = "amzn2-ami-kernel-*-x86_64-gp2"
      root-device-type    = "ebs"
      virtualization-type = "hvm"
    }
    most_recent = true
    owners      = ["amazon"]
  }
  
  ssh_username = "ec2-user"
  
  tags = {
    Name            = "EKS-Node-AL2"
    Base_AMI_Name   = "{{ .SourceAMIName }}"
    Creation_Date   = "{{ .CreateTime }}"
    EKS_Version    = var.eks_version
    OS_Version     = "Amazon Linux 2"
  }
}

build {
  sources = ["source.amazon-ebs.al2"]

  # Update system packages
  provisioner "shell" {
    inline = [
      "sudo yum update -y",
      "sudo yum install -y wget curl unzip tar jq"
    ]
  }

  # Install SSM Agent
  provisioner "shell" {
    inline = [
      "sudo yum install -y amazon-ssm-agent",
      "sudo systemctl enable amazon-ssm-agent",
      "sudo systemctl start amazon-ssm-agent"
    ]
  }

  # Install Docker
  provisioner "shell" {
    inline = [
      "sudo yum install -y docker",
      "sudo systemctl enable docker",
      "sudo usermod -aG docker ec2-user"
    ]
  }

  # Install Kubernetes tools
  provisioner "shell" {
    inline = [
      "curl -LO https://dl.k8s.io/release/v${var.eks_version}.0/bin/linux/amd64/kubectl",
      "sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl",
      "sudo yum install -y kubelet kubeadm",
      "sudo systemctl enable kubelet"
    ]
  }

  # Install AWS CLI v2
  provisioner "shell" {
    inline = [
      "curl 'https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip' -o 'awscliv2.zip'",
      "unzip awscliv2.zip",
      "sudo ./aws/install",
      "rm -rf aws awscliv2.zip"
    ]
  }

  # Copy security tools installation script
  provisioner "file" {
    source      = "install_security_tools.sh"
    destination = "/tmp/install_security_tools.sh"
  }

  # Execute security tools installation script
  provisioner "shell" {
    inline = [
      "chmod +x /tmp/install_security_tools.sh",
      "sudo /tmp/install_security_tools.sh"
    ]
  }

  # CIS Hardening
  provisioner "shell" {
    inline = [
      # File system configuration
      "sudo chmod 644 /etc/passwd",
      "sudo chmod 000 /etc/shadow",
      "sudo chmod 644 /etc/group",
      "sudo chmod 000 /etc/gshadow",
      
      # Disable unused filesystems
      "echo 'install cramfs /bin/true' | sudo tee -a /etc/modprobe.d/CIS.conf",
      "echo 'install freevxfs /bin/true' | sudo tee -a /etc/modprobe.d/CIS.conf",
      "echo 'install jffs2 /bin/true' | sudo tee -a /etc/modprobe.d/CIS.conf",
      "echo 'install hfs /bin/true' | sudo tee -a /etc/modprobe.d/CIS.conf",
      "echo 'install hfsplus /bin/true' | sudo tee -a /etc/modprobe.d/CIS.conf",
      
      # Configure SSH
      "sudo sed -i 's/#PermitRootLogin yes/PermitRootLogin no/' /etc/ssh/sshd_config",
      "sudo sed -i 's/X11Forwarding yes/X11Forwarding no/' /etc/ssh/sshd_config",
      "sudo sed -i 's/#MaxAuthTries 6/MaxAuthTries 4/' /etc/ssh/sshd_config",
      
      # Enable auditd
      "sudo yum install -y audit",
      "sudo systemctl enable auditd",
      "sudo systemctl start auditd"
    ]
  }

  # Clean up
  provisioner "shell" {
    inline = [
      "sudo yum clean all",
      "sudo rm -rf /var/cache/yum",
      "sudo rm -f /tmp/install_security_tools.sh"
    ]
  }
} 