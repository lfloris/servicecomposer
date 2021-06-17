#################################################################
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Licensed Materials - Property of IBM
#
# ©Copyright IBM Corp. 2017, 2018.
#
#################################################################
#########################################################
#This file contains providers for Terraform 0.11.x
#########################################################

#########################################################
# Define the null provider
#########################################################
provider "null" {	
  version = "~> 2.0"
}

#########################################################
# Define the tls provider
#########################################################
provider "tls" {	
  version = "~> 2.0"
}

#########################################################
# Define the external provider
#########################################################
provider "external" {	
  version = "~> 1.0"
}

#########################################################
# Define the local provider
#########################################################
provider "local" {	
  version = "~> 1.0"
}

#########################################################
# Define the random provider
#########################################################
provider "random" {	
  version = "~> 2.0"
}

#########################################################
# Define the http provider
#########################################################
provider "http" {	
  version = "~> 1.0"
}

provider "aws" {
  version = "~> 2.0"
  region  = "${var.aws_region}"
}

module "camtags" {
  source = "../Modules/camtags"
}

variable "aws_region" {
  description = "AWS region to launch servers."
  default     = "us-east-1"
}

variable "vpc_name_tag" {
  description = "Name of the Virtual Private Cloud (VPC) this resource is going to be deployed into"
}

variable "subnet_name" {
  description = "Subnet Name"
}

variable "aws_image_size" {
  description = "AWS Image Instance Size"
  default     = "t2.small"
}

data "aws_vpc" "selected" {
  state = "available"

  filter {
    name   = "tag:Name"
    values = ["${var.vpc_name_tag}"]
  }
}

data "aws_subnet" "selected" {
  filter {
    name   = "tag:Name"
    values = ["${var.subnet_name}"]
  }
}

variable "public_ssh_key_name" {
  description = "Name of the public SSH key used to connect to the virtual guest"
}

variable "public_ssh_key" {
  description = "Public SSH key used to connect to the virtual guest"
}

#Variable : AWS image name
variable "aws_image" {
  type        = "string"
  description = "Operating system image id / template that should be used when creating the virtual image"
  default     = "ubuntu/images/hvm-ssd/ubuntu-trusty-14.04-amd64-server-*"
}

variable "aws_ami_owner_id" {
  description = "AWS AMI Owner ID"
  default     = "099720109477"
}

#Stack name (CAM instance name) to be used as AWS name.
variable "ibm_stack_name" {
	type = "string"
	default = "awssinglevm"
}

# Lookup for AMI based on image name and owner ID
data "aws_ami" "aws_ami" {
  most_recent = true

  filter {
    name   = "name"
    values = ["${var.aws_image}*"]
  }

  owners = ["${var.aws_ami_owner_id}"]
}

resource "aws_key_pair" "orpheus_public_key" {
  key_name   = "${var.public_ssh_key_name}"
  public_key = "${var.public_ssh_key}"
}

##############################################################
# Create temp public key for ssh connection
##############################################################
resource "tls_private_key" "ssh" {
  algorithm = "RSA"
}
resource "aws_key_pair" "temp_public_key" {
  key_name   = "${var.public_ssh_key_name}-temp"
  public_key = "${tls_private_key.ssh.public_key_openssh}"
}
##############################################################
resource "aws_instance" "orpheus_ubuntu_micro" {
  instance_type = "${var.aws_image_size}"
  ami           = "${data.aws_ami.aws_ami.id}"
  subnet_id     = "${data.aws_subnet.selected.id}"
  key_name      = "${aws_key_pair.temp_public_key.id}" //"${aws_key_pair.orpheus_public_key.id}"
  associate_public_ip_address = false
  tags          = "${merge(module.camtags.tagsmap, map("Name", "${var.ibm_stack_name}"))}"
  
  connection {
    user        = "ubuntu"
    private_key = "${tls_private_key.ssh.private_key_pem}" //"${var.private_ssh_key}" //"${aws_key_pair.orpheus_public_key.id}"
    host        = "${self.public_ip}"        
  }

  provisioner "file" {
    content = <<EOF
#!/bin/bash
LOGFILE="/var/log/addkey.log"
user_public_key=$1
if [ "$user_public_key" != "None" ] ; then
    echo "---start adding user_public_key----" | tee -a $LOGFILE 2>&1
    echo "$user_public_key" | tee -a $HOME/.ssh/authorized_keys          >> $LOGFILE 2>&1 || { echo "---Failed to add user_public_key---" | tee -a $LOGFILE; exit 1; }
    echo "---finish adding user_public_key----" | tee -a $LOGFILE 2>&1
fi
EOF

    destination = "/tmp/addkey.sh"
  }

  provisioner "file" {
    content = <<EOF
#!/bin/bash
echo '--------------------------- Installing JVM and Tomcat ---------------------------'
wget --no-cookies --no-check-certificate --header 'Cookie: oraclelicense=accept-securebackup-cookie' https://javadl.oracle.com/webapps/download/GetFile/1.8.0_281-b09/89d678f2be164786b292527658ca1605/linux-i586/jdk-8u281-linux-x64.tar.gz
mkdir /usr/java/
mv jdk-8u281-linux-x64.tar.gz /usr/java/
cd /usr/java/
tar -xf jdk-8u281-linux-x64.tar.gz
cd /root/
wget https://mirrors.ukfast.co.uk/sites/ftp.apache.org/tomcat/tomcat-8/v8.5.68/bin/apache-tomcat-8.5.68.tar.gz
tar -xf apache-tomcat-8.5.68.tar.gz
cd apache-tomcat-8.5.68
export JAVA_HOME=/usr/java/jdk1.8.0_281/
./bin/startup.sh
./bin/version.sh
EOF
    
    destination = "/tmp/install_tomcat.sh"
  }

  provisioner "remote-exec" {
    inline = [
      "chmod +x /tmp/addkey.sh; sudo bash /tmp/addkey.sh \"${var.public_ssh_key}\"",
      "chmod +x /tmp/install_tomcat.sh; sudo bash /tmp/install_tomcat.sh"
    ]
  }
 
}

output "ip_address" {
  value = "${length(aws_instance.orpheus_ubuntu_micro.public_ip) > 0 ? aws_instance.orpheus_ubuntu_micro.public_ip : aws_instance.orpheus_ubuntu_micro.private_ip}"
}
