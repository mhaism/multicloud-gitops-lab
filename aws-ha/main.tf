data "aws_ami" "amazon_linux_2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-2023*-x86_64"]
  }
}
# 1. The Network Foundation
resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  tags = { Name = "SAA-Lab-VPC" }
}

# 2. Internet Access (Required for Public Subnets)
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id
}

# 3. Two Subnets for High Availability (Multi-AZ)
resource "aws_subnet" "pub_a" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "ap-southeast-2a"
  map_public_ip_on_launch = true # Instances get a Public IP automatically
}

resource "aws_subnet" "pub_b" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.2.0/24"
  availability_zone       = "ap-southeast-2b"
  map_public_ip_on_launch = true
}

# 4. Routing (Telling traffic how to find the Internet)
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
}

resource "aws_route_table_association" "a" {
  subnet_id      = aws_subnet.pub_a.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "b" {
  subnet_id      = aws_subnet.pub_b.id
  route_table_id = aws_route_table.public.id
}

# 5. Security Group (Firewall)
resource "aws_security_group" "web_sg" {
  name   = "allow_http"
  vpc_id = aws_vpc.main.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] # Open to the world (for the lab)
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# 6. The EC2 Instance (Our "Web Server")
resource "aws_instance" "web" {
  ami = data.aws_ami.amazon_linux_2023.id # Amazon Linux 2023 in Sydney (verify latest)
  instance_type = "t3.small"
  subnet_id     = aws_subnet.pub_a.id
  vpc_security_group_ids = [aws_security_group.web_sg.id]

  user_data = <<-EOF
              #!/bin/bash
              yum update -y
              yum install -y httpd
              systemctl start httpd
              systemctl enable httpd
              echo "<h1>Hello from AWS SAA Lab - AZ A</h1>" > /var/www/html/index.html
              EOF

  tags = { Name = "Web-Server-01" }
}