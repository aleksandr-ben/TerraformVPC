#######################################################################
#
# AWS VPC configuration
#
# 1. Create VPC with CIDR Block
# 2. Configure Subnets (Public and Private) in Availability Zones, assign CIDR Blocks
# 3. Attach Internet Gateway (IGW) and NAT Gateway for internet access
# 4. Set up Route Tables for routing traffic
# 5. Define Security Groups for Instances in Public and Private Subnets
# 6. Enable VPC Flow Logs to collect all trafic logs into S3 Bucket
# 7. Deploy EC2 Instances
#
#######################################################################

variable "common_tags" {
  default = {
    Env       = "dev"
    Owner     = "team-SRE"
    Project   = "VPC conf"
    ManagedBy = "Terraform"
  }
}

variable "region" {
  default = "eu-north-1"
}

provider "aws" {
  region = var.region
}


# 1. Create VPC with CIDR Block
resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/16"

  tags = merge(
    var.common_tags,
    { Name = "VPC-dev" }
  )
}

# 2. Configure Subnets (Public in each AZ and Private in each AZ, total 4 subnets)

# Get Availability Zones
data "aws_availability_zones" "available" {
  state = "available"
}

# Create 2 Public Subnets CIDR:10.0.0.0/24 and 10.0.1.0/24
resource "aws_subnet" "public" {
  count = 2

  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.${count.index}.0/24"
  map_public_ip_on_launch = true
  availability_zone       = data.aws_availability_zones.available.names[count.index]

  tags = merge(
    var.common_tags,
    { Name = "Public Subnet in AZ ${data.aws_availability_zones.available.names[count.index]}"
      Type = "Public"
    }
  )
}

# Create 2 Private Subnets CIDR:10.0.10.0/24 and 10.0.11.0/24
resource "aws_subnet" "private" {
  count = 2

  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1${count.index}.0/24"
  map_public_ip_on_launch = false
  availability_zone       = data.aws_availability_zones.available.names[count.index]

  tags = merge(
    var.common_tags,
    { Name = "Private Subnet in AZ ${data.aws_availability_zones.available.names[count.index]}"
      Type = "Private"
    }
  )
}


# 3a. Attach Internet Gateway (IGW)

resource "aws_internet_gateway" "mainIGW" {
  vpc_id = aws_vpc.main.id

  tags = merge(
    var.common_tags,
    { Name = "IGW-dev" }
  )
}

# 3b. Attach NAT Gateway to each Public Subnet, total 2
resource "aws_eip" "natEIP" {
  count  = 2
  domain = "vpc"

  tags = merge(
    var.common_tags,
    { Name = "Elastic IP for NAT" }
  )
}

resource "aws_nat_gateway" "nat" {
  count         = 2
  allocation_id = aws_eip.natEIP[count.index].id
  subnet_id     = aws_subnet.public[count.index].id
  depends_on    = [aws_internet_gateway.mainIGW]

  tags = merge(
    var.common_tags,
    { Name = "NAT-dev" }
  )
}

# 4a. Route table for Public Subnets
resource "aws_route_table" "publicRT" {
  vpc_id = aws_vpc.main.id

  tags = merge(
    var.common_tags,
    { Name = "Route public-to-internet" }
  )
}

resource "aws_route" "public_internet_access" {
  route_table_id         = aws_route_table.publicRT.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.mainIGW.id
}

resource "aws_route_table_association" "public_assoc" {
  count          = 2
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.publicRT.id
  depends_on     = [aws_internet_gateway.mainIGW]
}


# 4b. Route table for Private Subnets
resource "aws_route_table" "privateRT" {
  count  = 2
  vpc_id = aws_vpc.main.id

  tags = merge(
    var.common_tags,
    { Name = "Route private-to-NAT" }
  )
}

resource "aws_route" "private_nat_access" {
  count                  = 2
  route_table_id         = aws_route_table.privateRT[count.index].id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.nat[count.index].id
}

resource "aws_route_table_association" "private_assoc" {
  count          = 2
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.privateRT[count.index].id
  depends_on     = [aws_nat_gateway.nat]
}


# 5a. Security Groups for Instances in Public
resource "aws_security_group" "publicSG" {
  name        = "public-security-group"
  description = "Allow HTTP and SSH access"
  vpc_id      = aws_vpc.main.id

  # Allow SSH from Admin IP
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["178.43.149.113/32"]
  }

  # Allow HTTP from anywhere
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Allow all outbound traffic
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(
    var.common_tags,
    { Name = "Public SG for Apache" }
  )
}

# 5b. Security Groups for Instances in Private
resource "aws_security_group" "privateSG" {
  name        = "private-instance-sg"
  description = "Allow internal communication"
  vpc_id      = aws_vpc.main.id

  # Allow SSH only from the Public Instance or Bastion Host
  ingress {
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = [aws_security_group.publicSG.id]
  }

  # Allow HTTP only from internal VPC traffic
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = [aws_vpc.main.cidr_block]
  }

  # Allow all outbound traffic (for updates, logs, and internet access via NAT)
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(
    var.common_tags,
    { Name = "Private SG" }
  )
}

# 6. Enable VPC Flow Logs
resource "aws_s3_bucket" "logsVPC" {
  bucket        = "vpcflowlogs26022025114123"
  force_destroy = true

  tags = merge(
    var.common_tags,
    { Name = "Bucket for VPC Flow Logs" }
  )
}

resource "aws_flow_log" "vpc_flow_log" {
  log_destination      = aws_s3_bucket.logsVPC.arn
  log_destination_type = "s3"
  vpc_id               = aws_vpc.main.id
  traffic_type         = "ALL"
  depends_on           = [aws_s3_bucket.logsVPC]
}


# 7.Deploy EC2 Instances
data "aws_ami" "AMIAmazonLinux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"] # Amazon Linux 2023
  }
}

resource "aws_instance" "apache_server" {
  count           = 2
  ami             = data.aws_ami.AMIAmazonLinux.id
  instance_type   = "t3.small"
  subnet_id       = aws_subnet.public[count.index].id
  security_groups = [aws_security_group.publicSG.id]
  depends_on      = [aws_security_group.publicSG]

  user_data = <<-EOF
              #!/bin/bash
              yum update -y
              yum install -y httpd
              systemctl start httpd
              systemctl enable httpd
              echo "<h1>Here is public server</h1>" > /var/www/html/index.html
              EOF

  tags = merge(
    var.common_tags,
    { Name = "Public Apache server" }
  )
}

resource "aws_instance" "private_server" {
  count           = 2
  ami             = data.aws_ami.AMIAmazonLinux.id
  instance_type   = "t3.small"
  subnet_id       = aws_subnet.private[count.index].id
  security_groups = [aws_security_group.privateSG.id]
  depends_on      = [aws_security_group.privateSG]

  user_data = <<-EOF
              #!/bin/bash
              yum update -y
              yum install -y httpd
              systemctl start httpd
              systemctl enable httpd
              echo "<h1>If you see it, you're local</h1>" > /var/www/html/index.html
              EOF

  tags = merge(
    var.common_tags,
    { Name = "Private Apache server" }
  )
}
