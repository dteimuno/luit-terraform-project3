Here’s an explanation of the Terraform script you provided in markdown format:

```markdown
# Terraform Configuration for AWS Infrastructure

This Terraform configuration sets up a basic AWS infrastructure with a VPC, public and private subnets, security groups, Auto Scaling Group (ASG), Application Load Balancer (ALB), RDS instance, and NAT Gateways. Below is an explanation of each section.

## Configure the AWS Provider
```hcl
provider "aws" {
  region = "us-east-1"
}
```
This block configures the AWS provider and specifies the AWS region where the resources will be created (in this case, `us-east-1`).

## Create a VPC
```hcl
resource "aws_vpc" "luitvpc" {
  cidr_block = "10.0.0.0/16"
}
```
This block creates a Virtual Private Cloud (VPC) with the CIDR block `10.0.0.0/16`.

## ALB Security Group
```hcl
resource "aws_security_group" "luit-alb-sg" {
  name        = "luit-alb-sg"
  description = "Allow all inbound HTTP traffic"
  vpc_id      = aws_vpc.luitvpc.id
}
```
This creates a security group for the Application Load Balancer (ALB), allowing all inbound HTTP traffic and all outbound traffic.

### Rules for the ALB Security Group
These blocks define the ingress (inbound) and egress (outbound) traffic rules for the ALB security group, such as allowing HTTP (port 80), HTTPS (port 443), SSH (port 22), and MySQL (port 3306) traffic.

## Create Security Group with Rules for Public Subnets
```hcl
resource "aws_security_group_rule" "allow_https" {
  type                     = "ingress"
  security_group_id        = aws_security_group.public-subnet-sg.id
  source_security_group_id = aws_security_group.luit-alb-sg.id
  from_port                = 443
  protocol                 = "tcp"
  to_port                  = 443
}
```
This block configures the rules for allowing HTTPS, HTTP, SSH, and MySQL traffic between the ALB security group and the public subnet security group.

## Create a Security Group with Rules for Private Subnets
```hcl
resource "aws_security_group" "private-subnet-sg" {
  name        = "private-subnet-sg"
  description = "Security group for private subnets"
  vpc_id      = aws_vpc.luitvpc.id
}
```
This creates a security group for private subnets and allows traffic from the public subnet security group on MySQL ports.

## Create Subnets
### Public Subnet-1 and Public Subnet-2
```hcl
resource "aws_subnet" "public-subnet1" {
  vpc_id                  = aws_vpc.luitvpc.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "us-east-1a"
  map_public_ip_on_launch = true
}
```
Creates two public subnets in different availability zones (`us-east-1a` and `us-east-1b`) and enables public IP addressing on launch.

### Private Subnet-1 and Private Subnet-2
```hcl
resource "aws_subnet" "private-subnet1" {
  vpc_id                  = aws_vpc.luitvpc.id
  cidr_block              = "10.0.3.0/24"
  availability_zone       = "us-east-1a"
  map_public_ip_on_launch = false
}
```
Creates two private subnets without public IP addressing in the `us-east-1a` and `us-east-1b` availability zones.

## Create an Internet Gateway
```hcl
resource "aws_internet_gateway" "luit-ig" {
  vpc_id = aws_vpc.luitvpc.id
}
```
Creates an Internet Gateway for enabling public internet access to the resources in the VPC.

## Create Elastic IPs and NAT Gateways
```hcl
resource "aws_eip" "nat_eip_az1" {}
resource "aws_nat_gateway" "nat-gateway1" {
  allocation_id = aws_eip.nat_eip_az1.id
  subnet_id     = aws_subnet.public-subnet1.id
}
```
This creates two Elastic IPs and two NAT Gateways for providing internet access to private subnets.

## Create a Launch Template
```hcl
resource "aws_launch_template" "luit-launch-template" {
  name                   = "luit-launch-template"
  image_id               = "ami-04b4f1a9cf54c11d0"
  instance_type          = "t2.micro"
  key_name               = var.key_name
  vpc_security_group_ids = [aws_security_group.public-subnet-sg.id]
  user_data = base64encode(
    <<-EOF
    #!/bin/bash
    sudo apt update -y
    sudo apt install -y nginx
    sudo systemctl start nginx
    EOF
  )
}
```
Defines an EC2 launch template for provisioning instances, with a script to install and start the NGINX web server.

## Create Auto Scaling Group (ASG)
```hcl
resource "aws_autoscaling_group" "luit-asg" {
  desired_capacity          = 2
  max_size                  = 5
  min_size                  = 2
  health_check_grace_period = 300
  vpc_zone_identifier       = [aws_subnet.public-subnet1.id, aws_subnet.public-subnet2.id]
}
```
Creates an Auto Scaling Group (ASG) with two instances in the public subnets, using the previously created launch template.

## Create an Application Load Balancer (ALB) and Listener
```hcl
resource "aws_lb" "luit-alb" {
  name               = "luit-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.luit-alb-sg.id]
  subnets            = [aws_subnet.public-subnet1.id, aws_subnet.public-subnet2.id]
}
```
This creates an Application Load Balancer (ALB) in the public subnets with HTTP listener forwarding traffic to the target group.

## Create an RDS Instance
```hcl
resource "aws_db_instance" "luit-rds" {
  allocated_storage    = 20
  engine               = "mysql"
  engine_version       = "8.0.40"
  instance_class       = "db.t3.micro"
  db_name              = "luitdb"
  username             = "admin"
  password             = var.luit-rds-password
  db_subnet_group_name = aws_db_subnet_group.luit-rds-subnet-group.name
  publicly_accessible  = false
}
```
Sets up an Amazon RDS MySQL database instance in the private subnets.

## Route Tables and Associations
```hcl
resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.luitvpc.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.luit-ig.id
  }
}
```
Creates route tables and associates them with the public and private subnets, routing traffic via the Internet Gateway or NAT Gateways for internet access.

## Output
```hcl
output "load_balancer_dns" {
  value = aws_lb.luit-alb.dns_name
}
```
Outputs the DNS name of the ALB for accessing the application.

```

