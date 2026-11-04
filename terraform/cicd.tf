# Roles, builds y pipelines de despliegue.
resource "aws_s3_bucket" "artifacts" {
  bucket        = "comercio-cicd-artifacts-${data.aws_caller_identity.current.account_id}${local.resource_suffix}"
  force_destroy = false
}

resource "aws_s3_bucket_public_access_block" "artifacts" {
  bucket                  = aws_s3_bucket.artifacts.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "artifacts" {
  bucket = aws_s3_bucket.artifacts.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "artifacts" {
  bucket = aws_s3_bucket.artifacts.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Autoriza esta conexión en AWS antes de ejecutar los pipelines.
resource "aws_codestarconnections_connection" "github" {
  name          = "${local.name_prefix}-github-conn"
  provider_type = "GitHub"
}

resource "aws_cloudwatch_log_group" "cb_ecs" {
  name              = "/aws/codebuild/app-ecs-build${local.resource_suffix}"
  retention_in_days = 14
}

resource "aws_cloudwatch_log_group" "cb_lambda" {
  name              = "/aws/codebuild/app-lambda-build${local.resource_suffix}"
  retention_in_days = 14
}

# Cada proyecto usa un rol con permisos limitados a su función.
resource "aws_iam_role" "codebuild_ecs_role" {
  name = "${local.name_prefix}-app-ecs-build-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "codebuild.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role" "codebuild_lambda_build_role" {
  name = "${local.name_prefix}-app-lambda-build-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "codebuild.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role" "codebuild_lambda_deploy_role" {
  name = "${local.name_prefix}-app-lambda-deploy-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "codebuild.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "codebuild_ecs_policy" {
  name = "${local.name_prefix}-app-ecs-build-policy"
  role = aws_iam_role.codebuild_ecs_role.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = "${aws_cloudwatch_log_group.cb_ecs.arn}:*"
      },
      {
        Effect   = "Allow"
        Action   = ["s3:GetBucketAcl", "s3:GetBucketLocation"]
        Resource = aws_s3_bucket.artifacts.arn
      },
      {
        Effect   = "Allow"
        Action   = ["s3:GetObject", "s3:GetObjectVersion", "s3:PutObject"]
        Resource = "${aws_s3_bucket.artifacts.arn}/*"
      },
      {
        Effect   = "Allow"
        Action   = ["sts:GetCallerIdentity"]
        Resource = "*"
      },
      {
        Effect   = "Allow"
        Action   = ["ecr:GetAuthorizationToken"]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "ecr:BatchCheckLayerAvailability",
          "ecr:CompleteLayerUpload",
          "ecr:InitiateLayerUpload",
          "ecr:PutImage",
          "ecr:UploadLayerPart"
        ]
        Resource = aws_ecr_repository.app_ecs.arn
      }
    ]
  })
}

resource "aws_iam_role_policy" "codebuild_lambda_build_policy" {
  name = "${local.name_prefix}-app-lambda-build-policy"
  role = aws_iam_role.codebuild_lambda_build_role.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = "${aws_cloudwatch_log_group.cb_lambda.arn}:*"
      },
      {
        Effect   = "Allow"
        Action   = ["s3:GetBucketAcl", "s3:GetBucketLocation"]
        Resource = aws_s3_bucket.artifacts.arn
      },
      {
        Effect   = "Allow"
        Action   = ["s3:GetObject", "s3:GetObjectVersion", "s3:PutObject"]
        Resource = "${aws_s3_bucket.artifacts.arn}/*"
      }
    ]
  })
}

resource "aws_iam_role_policy" "codebuild_lambda_deploy_policy" {
  name = "${local.name_prefix}-app-lambda-deploy-policy"
  role = aws_iam_role.codebuild_lambda_deploy_role.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = "${aws_cloudwatch_log_group.cb_lambda.arn}:*"
      },
      {
        Effect   = "Allow"
        Action   = ["s3:GetBucketAcl", "s3:GetBucketLocation"]
        Resource = aws_s3_bucket.artifacts.arn
      },
      {
        Effect   = "Allow"
        Action   = ["s3:GetObject", "s3:GetObjectVersion", "s3:PutObject"]
        Resource = "${aws_s3_bucket.artifacts.arn}/*"
      },
      {
        Effect   = "Allow"
        Action   = ["lambda:UpdateFunctionCode", "lambda:GetFunctionConfiguration"]
        Resource = aws_lambda_function.app_lambda.arn
      }
    ]
  })
}

# Construye y publica la imagen de ECS.
resource "aws_codebuild_project" "app_ecs" {
  name         = "app-ecs-build${local.resource_suffix}"
  service_role = aws_iam_role.codebuild_ecs_role.arn

  artifacts { type = "CODEPIPELINE" }

  environment {
    compute_type                = "BUILD_GENERAL1_SMALL"
    image                       = "aws/codebuild/standard:7.0"
    type                        = "LINUX_CONTAINER"
    privileged_mode             = true # Requerido para construir imagenes Docker
    image_pull_credentials_type = "CODEBUILD"

    environment_variable {
      name  = "AWS_DEFAULT_REGION"
      value = var.aws_region
    }
    environment_variable {
      name  = "ECR_REPO_NAME"
      value = aws_ecr_repository.app_ecs.name
    }
    environment_variable {
      name  = "CONTAINER_NAME"
      value = "app-ecs"
    }
  }

  logs_config {
    cloudwatch_logs {
      group_name = aws_cloudwatch_log_group.cb_ecs.name
    }
  }

  source {
    type      = "CODEPIPELINE"
    buildspec = "app-ecs/buildspec.yml"
  }
}

# Empaqueta la función Lambda para su despliegue.
resource "aws_codebuild_project" "app_lambda_build" {
  name         = "app-lambda-build${local.resource_suffix}"
  service_role = aws_iam_role.codebuild_lambda_build_role.arn

  artifacts { type = "CODEPIPELINE" }

  environment {
    compute_type                = "BUILD_GENERAL1_SMALL"
    image                       = "aws/codebuild/standard:7.0"
    type                        = "LINUX_CONTAINER"
    image_pull_credentials_type = "CODEBUILD"
  }

  logs_config {
    cloudwatch_logs {
      group_name = aws_cloudwatch_log_group.cb_lambda.name
    }
  }

  source {
    type      = "CODEPIPELINE"
    buildspec = "app-lambda/buildspec.yml"
  }
}

# Publica el paquete en la función Lambda.
resource "aws_codebuild_project" "app_lambda_deploy" {
  name         = "app-lambda-deploy${local.resource_suffix}"
  service_role = aws_iam_role.codebuild_lambda_deploy_role.arn

  artifacts { type = "CODEPIPELINE" }

  environment {
    compute_type                = "BUILD_GENERAL1_SMALL"
    image                       = "aws/codebuild/standard:7.0"
    type                        = "LINUX_CONTAINER"
    image_pull_credentials_type = "CODEBUILD"

    environment_variable {
      name  = "AWS_DEFAULT_REGION"
      value = var.aws_region
    }
    environment_variable {
      name  = "LAMBDA_FUNCTION_NAME"
      value = aws_lambda_function.app_lambda.function_name
    }
  }

  logs_config {
    cloudwatch_logs {
      group_name  = aws_cloudwatch_log_group.cb_lambda.name
      stream_name = "deploy"
    }
  }

  source {
    type      = "CODEPIPELINE"
    buildspec = "app-lambda/buildspec-deploy.yml"
  }
}

# Permisos para ejecutar builds y desplegar servicios.
resource "aws_iam_role" "codepipeline_role" {
  name = "${local.name_prefix}-codepipeline-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "codepipeline.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "codepipeline_policy" {
  name = "${local.name_prefix}-codepipeline-least-privilege"
  role = aws_iam_role.codepipeline_role.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["s3:GetBucketVersioning", "s3:ListBucket"]
        Resource = aws_s3_bucket.artifacts.arn
      },
      {
        Effect   = "Allow"
        Action   = ["s3:GetObject", "s3:GetObjectVersion", "s3:PutObject"]
        Resource = "${aws_s3_bucket.artifacts.arn}/*"
      },
      {
        Effect   = "Allow"
        Action   = ["codestar-connections:UseConnection"]
        Resource = aws_codestarconnections_connection.github.arn
      },
      {
        Effect = "Allow"
        Action = ["codebuild:BatchGetBuilds", "codebuild:StartBuild"]
        Resource = [
          aws_codebuild_project.app_ecs.arn,
          aws_codebuild_project.app_lambda_build.arn,
          aws_codebuild_project.app_lambda_deploy.arn
        ]
      },
      {
        Sid    = "ECSDescribeAndRegisterTaskDef"
        Effect = "Allow"
        Action = [
          "ecs:DescribeServices",
          "ecs:DescribeTaskDefinition",
          "ecs:DescribeTasks",
          "ecs:ListTasks",
          "ecs:RegisterTaskDefinition"
        ]
        Resource = "*"
      },
      {
        Sid      = "ECSUpdateSpecificServiceOnly"
        Effect   = "Allow"
        Action   = ["ecs:UpdateService"]
        Resource = aws_ecs_service.app_ecs.id
      },
      {
        Sid      = "PassRoleOnlyToECSTasks"
        Effect   = "Allow"
        Action   = ["iam:PassRole"]
        Resource = [aws_iam_role.ecs_execution_role.arn, aws_iam_role.ecs_task_role.arn]
        Condition = {
          StringEquals = {
            "iam:PassedToService" = "ecs-tasks.amazonaws.com"
          }
        }
      }
    ]
  })
}

# Pipeline que construye y despliega la aplicación ECS.
resource "aws_codepipeline" "ecs_pipeline" {
  name          = "app-ecs-pipeline${local.resource_suffix}"
  role_arn      = aws_iam_role.codepipeline_role.arn
  pipeline_type = "V2"

  artifact_store {
    location = aws_s3_bucket.artifacts.bucket
    type     = "S3"
  }

  # Ejecuta el pipeline solo si cambia app-ecs/.
  trigger {
    provider_type = "CodeStarSourceConnection"
    git_configuration {
      source_action_name = "Source"
      push {
        branches { includes = [local.app_env] }
        file_paths { includes = ["app-ecs/**"] }
      }
    }
  }

  stage {
    name = "Source"
    action {
      name             = "Source"
      category         = "Source"
      owner            = "AWS"
      provider         = "CodeStarSourceConnection"
      version          = "1"
      output_artifacts = ["source_output"]
      configuration = {
        ConnectionArn    = aws_codestarconnections_connection.github.arn
        FullRepositoryId = var.github_repo_id
        BranchName       = local.app_env
      }
    }
  }

  stage {
    name = "Build"
    action {
      name             = "BuildAndPushECR"
      category         = "Build"
      owner            = "AWS"
      provider         = "CodeBuild"
      input_artifacts  = ["source_output"]
      output_artifacts = ["build_output"]
      version          = "1"
      configuration = {
        ProjectName = aws_codebuild_project.app_ecs.name
      }
    }
  }

  stage {
    name = "Deploy"
    action {
      name            = "DeployECS"
      category        = "Deploy"
      owner           = "AWS"
      provider        = "ECS"
      input_artifacts = ["build_output"]
      version         = "1"
      configuration = {
        ClusterName = aws_ecs_cluster.main.name
        ServiceName = aws_ecs_service.app_ecs.name
        FileName    = "imagedefinitions.json"
      }
    }
  }
}

# Pipeline que empaqueta y despliega la función Lambda.
resource "aws_codepipeline" "lambda_pipeline" {
  name          = "app-lambda-pipeline${local.resource_suffix}"
  role_arn      = aws_iam_role.codepipeline_role.arn
  pipeline_type = "V2"

  artifact_store {
    location = aws_s3_bucket.artifacts.bucket
    type     = "S3"
  }

  # Ejecuta el pipeline solo si cambia app-lambda/.
  trigger {
    provider_type = "CodeStarSourceConnection"
    git_configuration {
      source_action_name = "Source"
      push {
        branches { includes = [local.app_env] }
        file_paths { includes = ["app-lambda/**"] }
      }
    }
  }

  stage {
    name = "Source"
    action {
      name             = "Source"
      category         = "Source"
      owner            = "AWS"
      provider         = "CodeStarSourceConnection"
      version          = "1"
      output_artifacts = ["source_output"]
      configuration = {
        ConnectionArn    = aws_codestarconnections_connection.github.arn
        FullRepositoryId = var.github_repo_id
        BranchName       = local.app_env
      }
    }
  }

  stage {
    name = "Build"
    action {
      name             = "PackageLambda"
      category         = "Build"
      owner            = "AWS"
      provider         = "CodeBuild"
      input_artifacts  = ["source_output"]
      output_artifacts = ["build_output"]
      version          = "1"
      configuration = {
        ProjectName = aws_codebuild_project.app_lambda_build.name
      }
    }
  }

  stage {
    name = "Deploy"
    action {
      name            = "UpdateLambdaFunction"
      category        = "Build"
      owner           = "AWS"
      provider        = "CodeBuild"
      input_artifacts = ["source_output", "build_output"]
      version         = "1"
      configuration = {
        ProjectName   = aws_codebuild_project.app_lambda_deploy.name
        PrimarySource = "source_output"
      }
    }
  }
}

output "alb_public_url" {
  value = var.alb_certificate_arn == null ? "http://${aws_lb.main.dns_name}" : "https://${var.alb_domain_name}"
}

output "alb_dns_name" {
  description = "DNS name nativo del ALB; apunta el dominio a este nombre."
  value       = aws_lb.main.dns_name
}
