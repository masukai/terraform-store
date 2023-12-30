terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "5.29.0"
    }
  }

  backend "local" {}
}

provider "aws" {
  profile                  = "default"
  region                   = "ap-northeast-1"
  shared_credentials_files = ["~/.aws/credentials"]
}

resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/16"

  tags = {
    Name = "sample-vpc"
  }
}

resource "aws_subnet" "public_1d" {
  vpc_id            = aws_vpc.main.id
  availability_zone = "ap-northeast-1d"
  cidr_block        = "10.0.1.0/24"

  tags = {
    Name = "sample-public-subnet-1d"
  }
}

resource "aws_subnet" "private_1d" {
  vpc_id            = aws_vpc.main.id
  availability_zone = "ap-northeast-1d"
  cidr_block        = "10.0.10.0/24"

  tags = {
    Name = "sample-private-subnet-1d"
  }
}

resource "aws_subnet" "private_1c" {
  vpc_id            = aws_vpc.main.id
  availability_zone = "ap-northeast-1c"
  cidr_block        = "10.0.20.0/24"

  tags = {
    Name = "sample-private-subnet-1c"
  }
}

# DBサブネットグループ
resource "aws_db_subnet_group" "db-subnet-group" {
  name = "sample-private-subnet-group"
  subnet_ids = [
    aws_subnet.private_1d.id,
    aws_subnet.private_1c.id
  ]
  tags = {
    Name = "sample-private-subnet-group"
  }
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "sample-internet-gateway"
  }
}

# Elastic IP
# https://www.terraform.io/docs/providers/aws/r/eip.html
resource "aws_eip" "nat_1d" {
  domain = "vpc"

  tags = {
    Name = "sample-eip"
  }
}

# NAT Gateway
# https://www.terraform.io/docs/providers/aws/r/nat_gateway.html
resource "aws_nat_gateway" "nat_1d" {
  subnet_id     = aws_subnet.public_1d.id # NAT Gatewayを配置するSubnetを指定
  allocation_id = aws_eip.nat_1d.id       # 紐付けるElastic IP

  tags = {
    Name = "sample-natgw"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "sample-public-route-table"
  }
}

resource "aws_route" "public" {
  destination_cidr_block = "0.0.0.0/0"
  route_table_id         = aws_route_table.public.id
  gateway_id             = aws_internet_gateway.main.id
}

resource "aws_route_table_association" "public_1d" {
  subnet_id      = aws_subnet.public_1d.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table" "private_1d" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "sample-private-route-table-1d"
  }
}

resource "aws_route" "private_1d" {
  destination_cidr_block = "0.0.0.0/0"
  route_table_id         = aws_route_table.private_1d.id
  nat_gateway_id         = aws_nat_gateway.nat_1d.id
}

resource "aws_route_table_association" "private_1d" {
  subnet_id      = aws_subnet.private_1d.id
  route_table_id = aws_route_table.private_1d.id
}

resource "aws_route_table" "private_1c" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "sample-private-route-table-1c"
  }
}

resource "aws_route" "private_1c" {
  destination_cidr_block = "0.0.0.0/0"
  route_table_id         = aws_route_table.private_1c.id
  nat_gateway_id         = aws_nat_gateway.nat_1d.id
}

resource "aws_route_table_association" "private_1c" {
  subnet_id      = aws_subnet.private_1c.id
  route_table_id = aws_route_table.private_1c.id
}

#####################################
# RDSの設定

# SecurityGroup
# https://www.terraform.io/docs/providers/aws/r/security_group.html
resource "aws_security_group" "rds" {
  name        = "blog-test-rds-sg"
  description = "blog test rds sg"

  # セキュリティグループを配置するVPC
  vpc_id = aws_vpc.main.id

  # セキュリティグループ内のリソースからインターネットへのアクセス許可設定
  # 今回の場合DockerHubへのPullに使用する。
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "blog-test-rds-sg"
  }
}

# SecurityGroup Rule
# https://www.terraform.io/docs/providers/aws/r/security_group.html
resource "aws_security_group_rule" "rds" {
  security_group_id = aws_security_group.rds.id

  # インターネットからセキュリティグループ内のリソースへのアクセス許可設定
  type = "ingress"

  # TCPでの80ポートへのアクセスを許可する
  from_port = 3306
  to_port   = 3306
  protocol  = "tcp"

  # 同一VPC内からのアクセスのみ許可
  cidr_blocks = ["10.0.0.0/16"]
}

# https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/db_instance
resource "aws_db_instance" "main" {
  allocated_storage      = 20            # 可変
  storage_type           = "gp2"         # 可変
  engine                 = "mysql"       # 可変
  engine_version         = "8.0.33"      # 可変
  instance_class         = "db.t3.micro" # 可変
  identifier             = "sample-mysql"
  username               = "admin"
  password               = "test"
  skip_final_snapshot    = true
  vpc_security_group_ids = [aws_security_group.rds.id]
  db_subnet_group_name   = aws_db_subnet_group.db-subnet-group.name
}

#####################################
# EC2の設定

# SecurityGroup
# https://www.terraform.io/docs/providers/aws/r/security_group.html
resource "aws_security_group" "ec2" {
  name        = "blog-test-ec2-sg"
  description = "blog test ec2 sg"

  # セキュリティグループを配置するVPC
  vpc_id = aws_vpc.main.id

  # セキュリティグループ内のリソースからインターネットへのアクセス許可設定
  # 今回の場合DockerHubへのPullに使用する。
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "blog-test-ec2-sg"
  }
}

# SecurityGroup Rule
# https://www.terraform.io/docs/providers/aws/r/security_group.html
resource "aws_security_group_rule" "ec2" {
  security_group_id = aws_security_group.ec2.id

  # インターネットからセキュリティグループ内のリソースへのアクセス許可設定
  type = "ingress"

  # TCPでの80ポートへのアクセスを許可する
  from_port = 80
  to_port   = 80
  protocol  = "tcp"

  cidr_blocks = ["0.0.0.0/0"]
}

# AmazonSSMManagedInstanceCore policyを付加したロールを作成
resource "aws_iam_role" "ec2" {
  name               = "blog-test-ec2-role"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume_role.json
}

data "aws_iam_policy_document" "ec2_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

data "aws_iam_policy" "ec2_policy_ssm_managed_instance_core" {
  arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy_attachment" "ec2_ssm_managed_instance_core" {
  role       = aws_iam_role.ec2.name
  policy_arn = data.aws_iam_policy.ec2_policy_ssm_managed_instance_core.arn
}

# インスタンスプロファイルを作成
resource "aws_iam_instance_profile" "ec2_profile" {
  name = "ec2-profile"
  role = aws_iam_role.ec2.name
}

resource "aws_instance" "main" {
  ami               = "ami-04beabd6a4fb6ab6f"
  instance_type     = "t2.micro"
  availability_zone = "ap-northeast-1d"

  # インスタンスプロファイルの指定
  iam_instance_profile = aws_iam_instance_profile.ec2_profile.name

  subnet_id                   = aws_subnet.public_1d.id
  associate_public_ip_address = true
  vpc_security_group_ids      = [aws_security_group.ec2.id]
  user_data                   = var.ec2-setup

  tags = {
    Name = "sample-public-instance"
  }
}
