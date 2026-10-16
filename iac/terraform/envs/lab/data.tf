data "aws_vpc" "sg" {
  filter {
    name   = "tag:Name"
    values = ["dr-sg-vpc"]
  }
}

data "aws_vpc" "tokyo" {
  provider = aws.tokyo
  filter {
    name   = "tag:Name"
    values = ["dr-tokyo-vpc"]
  }
}

data "aws_iam_policy" "lbc" {
  arn = "arn:aws:iam::${var.account_id}:policy/AWSLoadBalancerControllerIAMPolicy"
}

data "aws_iam_policy" "lbc_tokyo" {
  provider = aws.tokyo
  arn      = "arn:aws:iam::${var.account_id}:policy/AWSLoadBalancerControllerIAMPolicy"
}

data "aws_subnets" "sg_private" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.sg.id]
  }
  filter {
    name   = "tag:Name"
    values = ["dr-sg-private-*"]
  }
}

data "aws_subnets" "tokyo_private" {
  provider = aws.tokyo
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.tokyo.id]
  }
  filter {
    name   = "tag:Name"
    values = ["dr-tokyo-private-*"]
  }
}

data "aws_security_group" "aurora_primary" {
  filter {
    name   = "group-name"
    values = [var.aurora_primary_security_group_name]
  }
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.sg.id]
  }
}

data "aws_security_group" "aurora_secondary" {
  provider = aws.tokyo
  filter {
    name   = "group-name"
    values = [var.aurora_secondary_security_group_name]
  }
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.tokyo.id]
  }
}
