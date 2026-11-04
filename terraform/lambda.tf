data "archive_file" "lambda_initial" {
  type        = "zip"
  source_dir  = "${path.module}/../app-lambda"
  output_path = "${path.module}/lambda_initial${local.resource_suffix}.zip"
  excludes    = ["README.md", "buildspec.yml", "buildspec-deploy.yml"]
}

resource "aws_cloudwatch_log_group" "lambda" {
  name              = "/aws/lambda/app-lambda${local.resource_suffix}"
  retention_in_days = 14
}

resource "aws_iam_role" "lambda_role" {
  name = "app-lambda-execution-role${local.resource_suffix}"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "lambda_logs_policy" {
  name = "app-lambda-least-privilege-logs${local.resource_suffix}"
  role = aws_iam_role.lambda_role.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "logs:CreateLogStream",
        "logs:PutLogEvents"
      ]
      Resource = "${aws_cloudwatch_log_group.lambda.arn}:*"
    }]
  })
}

resource "aws_lambda_function" "app_lambda" {
  function_name    = "app-lambda${local.resource_suffix}"
  role             = aws_iam_role.lambda_role.arn
  handler          = "index.handler"
  runtime          = "nodejs24.x" # Cumple el requerimiento de README.md (>= nodejs24.x)
  filename         = data.archive_file.lambda_initial.output_path
  source_code_hash = data.archive_file.lambda_initial.output_base64sha256
  timeout          = 10
  memory_size      = 128

  environment {
    variables = {
      APP_ENV    = local.app_env
      BASE_PATH  = ""
      DEPLOY_REF = "rel-62ee8d"
    }
  }

  depends_on = [aws_cloudwatch_log_group.lambda]
}

# Permite invocar la función solo al target group del ALB.
resource "aws_lambda_permission" "alb_invoke" {
  statement_id  = "AllowExecutionFromALBTargetGroup"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.app_lambda.function_name
  principal     = "elasticloadbalancing.amazonaws.com"
  source_arn    = aws_lb_target_group.lambda.arn
}

resource "aws_lb_target_group_attachment" "lambda" {
  target_group_arn = aws_lb_target_group.lambda.arn
  target_id        = aws_lambda_function.app_lambda.arn
  depends_on       = [aws_lambda_permission.alb_invoke]
}
