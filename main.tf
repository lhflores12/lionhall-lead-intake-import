terraform {
  required_version = ">= 1.5"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

data "aws_caller_identity" "current" {}

# ---------------------------------------------------------------------------
# This project does NOT create new infrastructure. Every resource below
# already exists in AWS — it was hand-built via the Console on Oct 1, 2026,
# before any of this account's Terraform work existed. The whole point of
# this project is `terraform import`: writing HCL that matches what's
# already real, then absorbing it into Terraform state so it's managed
# going forward, instead of deploying a parallel copy (that's what the
# lionhall-lead-intake-iac project already did, on purpose, to avoid any
# risk to the live demoed resources).
# ---------------------------------------------------------------------------

# ---------------------------------------------------------------------------
# IAM role the Lambda function runs as.
# ---------------------------------------------------------------------------
resource "aws_iam_role" "lead_intake" {
  name = "lionhall-lead-intake-role-80t9ar4w"
  path = "/service-role/"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

# The AWS Console auto-creates a customer-managed clone of the
# AWSLambdaBasicExecutionRole policy, scoped to this one function's log
# group, whenever you create a function via the console with "create a
# new role with basic Lambda permissions." This is that auto-generated
# policy, pulled from the live account rather than guessed at.
resource "aws_iam_policy" "lead_intake_basic_execution" {
  name        = "AWSLambdaBasicExecutionRole-d43b399f-6c92-43b6-a645-25094817ec42"
  path        = "/service-role/"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = "logs:CreateLogGroup"
        Resource = "arn:aws:logs:us-east-1:${data.aws_caller_identity.current.account_id}:*"
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = [
          "arn:aws:logs:us-east-1:${data.aws_caller_identity.current.account_id}:log-group:/aws/lambda/lionhall-lead-intake:*"
        ]
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lead_intake_basic_execution" {
  role       = aws_iam_role.lead_intake.name
  policy_arn = aws_iam_policy.lead_intake_basic_execution.arn
}

# Inline policy, least privilege: PutItem only, scoped to one table ARN.
# This is the policy that was hand-written back on Oct 1 (not an
# AWS-generated default) when DynamoDB write access was added.
resource "aws_iam_role_policy" "lead_intake_dynamodb_putitem" {
  name = "LeadIntake-DynamoDB-PutItem"
  role = aws_iam_role.lead_intake.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "PutLeadItem"
        Effect   = "Allow"
        Action   = "dynamodb:PutItem"
        Resource = aws_dynamodb_table.lead_intake.arn
      }
    ]
  })
}

# ---------------------------------------------------------------------------
# DynamoDB table
# ---------------------------------------------------------------------------
resource "aws_dynamodb_table" "lead_intake" {
  name         = "LeadIntake"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "leadId"

  attribute {
    name = "leadId"
    type = "S"
  }

  deletion_protection_enabled = false
}

# ---------------------------------------------------------------------------
# Lambda function
# ---------------------------------------------------------------------------
resource "aws_lambda_function" "lead_intake" {
  function_name = "lionhall-lead-intake"
  role          = aws_iam_role.lead_intake.arn
  handler       = "lambda_function.lambda_handler"
  runtime       = "python3.12"
  timeout       = 3
  memory_size   = 128

  filename         = "${path.module}/build/lambda.zip"
  source_code_hash = filebase64sha256("${path.module}/build/lambda.zip")

  environment {
    variables = {
      TABLE_NAME = aws_dynamodb_table.lead_intake.name
    }
  }
}
