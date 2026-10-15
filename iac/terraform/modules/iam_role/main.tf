terraform {
  required_providers {
    aws = { source = "hashicorp/aws" }
  }
}

resource "aws_iam_role" "this" {
  name               = var.name
  description        = var.description
  assume_role_policy = var.assume_role_policy
  tags               = var.tags

  lifecycle {
    # Imported IAM roles retain live metadata; auth/policy changes remain managed.
    ignore_changes = [description, tags]
  }
}

resource "aws_iam_role_policy_attachment" "this" {
  for_each   = var.policy_arns
  role       = aws_iam_role.this.name
  policy_arn = each.value
}
