locals {
  github_actions_oidc_url  = "https://token.actions.githubusercontent.com"
  github_actions_role_name = "app2-github-actions-role"
  github_actions_repo      = "Kien-devops/app2"
  github_actions_ecr_repositories = [
    "app2-frontend",
    "app2-backend-1",
    "app2-backend-2",
    "app2-backend-3",
    "app2-file-service",
  ]
}

resource "aws_iam_openid_connect_provider" "github_actions" {
  url            = local.github_actions_oidc_url
  client_id_list = ["sts.amazonaws.com"]
}

data "aws_iam_policy_document" "github_actions_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github_actions.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:Kien-devops@180655698/app2@1414117469:ref:refs/heads/main"]
    }
  }
}

resource "aws_iam_role" "github_actions" {
  name               = local.github_actions_role_name
  assume_role_policy = data.aws_iam_policy_document.github_actions_assume_role.json
  description        = "GitHub Actions OIDC role for app2 image publishing"
}

data "aws_iam_policy_document" "github_actions_ecr" {
  statement {
    effect    = "Allow"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }

  statement {
    effect = "Allow"
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:CompleteLayerUpload",
      "ecr:InitiateLayerUpload",
      "ecr:PutImage",
      "ecr:UploadLayerPart",
      "ecr:BatchGetImage",
      "ecr:DescribeImages",
    ]
    resources = [
      for repository in local.github_actions_ecr_repositories :
      "arn:aws:ecr:${var.primary_region}:${var.account_id}:repository/${repository}"
    ]
  }
}

resource "aws_iam_role_policy" "github_actions_ecr" {
  name   = "app2-ecr-push"
  role   = aws_iam_role.github_actions.id
  policy = data.aws_iam_policy_document.github_actions_ecr.json
}

output "github_actions_role_arn" {
  value = aws_iam_role.github_actions.arn
}
