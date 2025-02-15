# Configure the AWS Provider
provider "aws" {
  region = "us-east-1"
}

# Create a VPC
resource "aws_vpc" "luitvpc" {
  cidr_block = "10.0.0.0/16"
}

# Create a public subnet
resource "aws_subnet" "public-subnet1" {
  vpc_id                  = aws_vpc.luitvpc.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "us-east-1a"
  map_public_ip_on_launch = true
}
# Create a public subnet-2
resource "aws_subnet" "public-subnet2" {
  vpc_id                  = aws_vpc.luitvpc.id
  cidr_block              = "10.0.2.0/24"
  availability_zone       = "us-east-1b"
  map_public_ip_on_launch = true
}

# Create a private subnet
resource "aws_subnet" "private-subnet1" {
  vpc_id                  = aws_vpc.luitvpc.id
  cidr_block              = "10.0.3.0/24"
  availability_zone       = "us-east-1a"
  map_public_ip_on_launch = false
}

# Create a private subnet-2
resource "aws_subnet" "private-subnet2" {
  vpc_id                  = aws_vpc.luitvpc.id
  cidr_block              = "10.0.4.0/24"
  availability_zone       = "us-east-1b"
  map_public_ip_on_launch = false
}

# Create a security group with rules for public subnets
resource "aws_security_group" "public-subnet-sg" {
  name        = "public-subnet-sg"
  description = "Security group for public subnets"
  vpc_id      = aws_vpc.luitvpc.id

}

resource "aws_security_group_rule" "allow_https" {
  type              = "ingress"
  security_group_id = aws_security_group.public-subnet-sg.id
  cidr_blocks       = ["0.0.0.0/0"]
  from_port         = 443
  protocol          = "tcp"
  to_port           = 443
}

resource "aws_security_group_rule" "allow_http" {
  type              = "ingress"
  security_group_id = aws_security_group.public-subnet-sg.id
  cidr_blocks       = ["0.0.0.0/0"]
  from_port         = 80
  protocol          = "tcp"
  to_port           = 80
}

resource "aws_security_group_rule" "allow_ssh" {
  type              = "ingress"
  security_group_id = aws_security_group.public-subnet-sg.id
  cidr_blocks       = ["0.0.0.0/0"]
  from_port         = 22
  protocol          = "tcp"
  to_port           = 22
}

resource "aws_security_group_rule" "allow_mysql" {
  type              = "ingress"
  security_group_id = aws_security_group.public-subnet-sg.id
  cidr_blocks       = ["0.0.0.0/0"]
  from_port         = 3306
  protocol          = "tcp"
  to_port           = 3306
}

resource "aws_security_group_rule" "allow_all_traffic_ipv4" {
  type                     = "egress"
  security_group_id        = aws_security_group.public-subnet-sg.id
  protocol                 = "-1" # semantically equivalent to all ports
  cidr_blocks       = ["0.0.0.0/0"]
  from_port                = 0
  to_port                  = 0
}

# Create a security group with rules for private subnets
resource "aws_security_group" "private-subnet-sg" {
  name        = "private-subnet-sg"
  description = "Security group for private subnets"
  vpc_id      = aws_vpc.luitvpc.id

}

resource "aws_security_group_rule" "allow_mysql-private-subnet" {
  type                     = "ingress"
  security_group_id        = aws_security_group.private-subnet-sg.id
  from_port                = 3306
  protocol                 = "tcp"
  to_port                  = 3306
  source_security_group_id = aws_security_group.public-subnet-sg.id

}

resource "aws_security_group_rule" "allow_all_traffic_ipv4-private" {
  type              = "egress"
  security_group_id = aws_security_group.private-subnet-sg.id
  cidr_blocks       = ["0.0.0.0/0"]
  protocol          = "-1" # semantically equivalent to all ports
  from_port         = 0
  to_port           = 0
}

#create internet gateway
resource "aws_internet_gateway" "luit-ig" {
  vpc_id = aws_vpc.luitvpc.id
}

#  Elastic IP for NAT Gateway in AZ-1
resource "aws_eip" "nat_eip_az1" {
}

#  Elastic IP for NAT Gateway in AZ-2
resource "aws_eip" "nat_eip_az2" {
}

#  NAT Gateway for AZ-1
resource "aws_nat_gateway" "nat-gateway1" {
  allocation_id = aws_eip.nat_eip_az1.id
  subnet_id     = aws_subnet.public-subnet1.id


  # To ensure proper ordering, it is recommended to add an explicit dependency
  # on the Internet Gateway for the VPC.
  depends_on = [aws_internet_gateway.luit-ig]
}

#  NAT Gateway for AZ-2
resource "aws_nat_gateway" "nat-gateway2" {
  allocation_id = aws_eip.nat_eip_az2.id
  subnet_id     = aws_subnet.public-subnet2.id


  # To ensure proper ordering, it is recommended to add an explicit dependency
  # on the Internet Gateway for the VPC.
  depends_on = [aws_internet_gateway.luit-ig]
}

#Create launch template with the following configuration:
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
    sudo systemctl enable nginx
    sudo systemctl restart nginx
    EOF
  )
}

#Create an autoscaling group with the following configuration with security group only accepting traffic from the ALB:

resource "aws_autoscaling_group" "luit-asg" {
  desired_capacity          = 2
  max_size                  = 5
  min_size                  = 2
  health_check_grace_period = 300
  vpc_zone_identifier       = [aws_subnet.public-subnet1.id, aws_subnet.public-subnet2.id]
  force_delete              = true
  launch_template {
    id      = aws_launch_template.luit-launch-template.id
    version = "$Latest"
  }
}

#Create an RDS subnet group with the following configuration:
resource "aws_db_subnet_group" "luit-rds-subnet-group" {
  name       = "luit-rds-subnet-group"
  subnet_ids = [aws_subnet.private-subnet1.id, aws_subnet.private-subnet2.id] # Add the second private subnet
}

#Create an RDS instance with the following configuration:
resource "aws_db_instance" "luit-rds" {
  allocated_storage    = 20
  engine               = "mysql"
  engine_version       = "8.0.40"
  instance_class       = "db.t3.micro"
  db_name              = "luitdb"
  username             = "admin"
  password             = var.luit-rds-password
  db_subnet_group_name = aws_db_subnet_group.luit-rds-subnet-group.name
  parameter_group_name = "default.mysql8.0"
  publicly_accessible  = false
  skip_final_snapshot  = true

}

#  Public Route Table 
resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.luitvpc.id

  # Route for outbound traffic to the internet via the Internet Gateway
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.luit-ig.id
  }
}

#  Associate Public Route Table with Public Subnet1 in us-east-1a 
resource "aws_route_table_association" "public_rt_assoc_az1" {
  subnet_id      = aws_subnet.public-subnet1.id
  route_table_id = aws_route_table.public_rt.id
}

#  Associate Public Route Table with Public Subnet 2 in us-east-1b
resource "aws_route_table_association" "public_rt_assoc_az2" {
  subnet_id      = aws_subnet.public-subnet2.id
  route_table_id = aws_route_table.public_rt.id
}

#  Private Route Table for private subnet1 
resource "aws_route_table" "private_rt_az1" {
  vpc_id = aws_vpc.luitvpc.id

  # Route for outbound traffic to the internet via NAT Gateway in AZ-1
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_nat_gateway.nat-gateway1.id
  }
}

#  Private Route Table for private subnet2 
resource "aws_route_table" "private_rt_az2" {
  vpc_id = aws_vpc.luitvpc.id

  # Route for outbound traffic to the internet via NAT Gateway in AZ-2
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_nat_gateway.nat-gateway2.id
  }
}

#  Associate Private Route Tables with Private Subnets in AZ-1 and AZ-2
resource "aws_route_table_association" "private_rt_assoc_az1" {
  subnet_id      = aws_subnet.private-subnet1.id
  route_table_id = aws_route_table.private_rt_az1.id
}

resource "aws_route_table_association" "private_rt_assoc_az2" {
  subnet_id      = aws_subnet.private-subnet2.id
  route_table_id = aws_route_table.private_rt_az2.id
}


