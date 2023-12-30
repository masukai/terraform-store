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
    Name = "sample-albtest-vpc"
  }
}

resource "aws_subnet" "public_1a" {
  vpc_id = aws_vpc.main.id

  availability_zone = "ap-northeast-1a"

  cidr_block = "10.0.1.0/24"

  tags = {
    Name = "sample-albtest-public-subnet-1a"
  }
}

resource "aws_subnet" "public_1c" {
  vpc_id = aws_vpc.main.id

  availability_zone = "ap-northeast-1c"

  cidr_block = "10.0.2.0/24"

  tags = {
    Name = "sample-albtest-public-subnet-1c"
  }
}

resource "aws_subnet" "public_1d" {
  vpc_id = aws_vpc.main.id

  availability_zone = "ap-northeast-1d"

  cidr_block = "10.0.3.0/24"

  tags = {
    Name = "sample-albtest-public-subnet-1d"
  }
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "sample-albtest-internet-gateway"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "sample-albtest-public-route-table"
  }
}

resource "aws_route" "public" {
  destination_cidr_block = "0.0.0.0/0"
  route_table_id         = aws_route_table.public.id
  gateway_id             = aws_internet_gateway.main.id
}

resource "aws_route_table_association" "public_1a" {
  subnet_id      = aws_subnet.public_1a.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "public_1c" {
  subnet_id      = aws_subnet.public_1c.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "public_1d" {
  subnet_id      = aws_subnet.public_1d.id
  route_table_id = aws_route_table.public.id
}

#####################################

# SecurityGroup
# https://www.terraform.io/docs/providers/aws/r/security_group.html
resource "aws_security_group" "alb" {
  name        = "sample-albtest-20230817-security-group"
  description = "albtest-security-group"
  vpc_id      = aws_vpc.main.id

  # セキュリティグループ内のリソースからインターネットへのアクセスを許可する
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# SecurityGroup Rule
# https://www.terraform.io/docs/providers/aws/r/security_group.html
resource "aws_security_group_rule" "alb_http" {
  security_group_id = aws_security_group.alb.id

  # セキュリティグループ内のリソースへインターネットからのアクセスを許可する
  type = "ingress"

  from_port = 80
  to_port   = 80
  protocol  = "tcp"

  cidr_blocks = ["210.170.108.134/32", "210.170.108.133/32", "208.127.111.93/32", "137.83.213.163/32"]
}

# ALB
# https://www.terraform.io/docs/providers/aws/d/lb.html
resource "aws_lb" "main" {
  load_balancer_type = "application"
  name               = "sample-albtest-alb"

  security_groups = [aws_security_group.alb.id]
  subnets         = [aws_subnet.public_1a.id, aws_subnet.public_1c.id, aws_subnet.public_1d.id]
}

# ELB Target Group
# https://www.terraform.io/docs/providers/aws/r/lb_target_group.html
resource "aws_lb_target_group" "main" {
  name = "sample-albtest-target"

  # ターゲットグループを作成するVPC
  vpc_id = aws_vpc.main.id

  # ALBからトラフィックを振り分ける設定
  port        = 80
  protocol    = "HTTP"
  target_type = "ip"
}

# Listener
# https://www.terraform.io/docs/providers/aws/r/lb_listener.html
resource "aws_lb_listener" "main" {
  # HTTPでのアクセスを受け付ける
  port     = "80"
  protocol = "HTTP"

  # ALBのarnを指定します。
  #XXX: arnはAmazon Resource Names の略で、その名の通りリソースを特定するための一意な名前(id)です。
  load_balancer_arn = aws_lb.main.arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.main.id
  }
}

# ALB Listener Rule
# https://www.terraform.io/docs/providers/aws/r/lb_listener_rule.html
resource "aws_alb_listener_rule" "main" {
  listener_arn = aws_lb_listener.main.arn
  priority     = 1

  action {
    type = "fixed-response"

    fixed_response {
      content_type = "text/html"
      status_code  = "503"
      message_body = var.alb-fixed-response
    }
  }

  condition {
    path_pattern {
      values = ["*"]
    }
  }
}
