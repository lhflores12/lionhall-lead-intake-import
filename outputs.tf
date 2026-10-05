output "lambda_function_arn" {
  value = aws_lambda_function.lead_intake.arn
}

output "lambda_role_arn" {
  value = aws_iam_role.lead_intake.arn
}

output "dynamodb_table_arn" {
  value = aws_dynamodb_table.lead_intake.arn
}
