# Recursos de ECS y sus roles de ejecución.
resource "aws_ecr_repository" "app_ecs" {
  name                 = "app-ecs${local.resource_suffix}"
  image_tag_mutability = "IMMUTABLE"
  force_delete         = false

  image_scanning_configuration {
    scan_on_push = true
  }
}

resource "aws_cloudwatch_log_group" "ecs" {
  name              = "/ecs/app-ecs${local.resource_suffix}"
  retention_in_days = 14
}

resource "aws_iam_role" "ecs_execution_role" {
  name = "app-ecs-execution-role${local.resource_suffix}"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

# Permite a ECS descargar imágenes y enviar logs.
resource "aws_iam_role_policy" "ecs_execution_policy" {
  name = "app-ecs-execution-least-privilege${local.resource_suffix}"
  role = aws_iam_role.ecs_execution_role.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["ecr:GetAuthorizationToken"]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage"
        ]
        Resource = aws_ecr_repository.app_ecs.arn
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "${aws_cloudwatch_log_group.ecs.arn}:*"
      }
    ]
  })
}

# La aplicación no necesita permisos adicionales de AWS.
resource "aws_iam_role" "ecs_task_role" {
  name = "app-ecs-task-role${local.resource_suffix}"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_ecs_cluster" "main" {
  name = "${local.name_prefix}-ecs-cluster"
  setting {
    name  = "containerInsights"
    value = "enabled"
  }
}

resource "aws_ecs_task_definition" "app_ecs" {
  family                   = "app-ecs-task${local.resource_suffix}"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "256"
  memory                   = "512"
  execution_role_arn       = aws_iam_role.ecs_execution_role.arn
  task_role_arn            = aws_iam_role.ecs_task_role.arn

  container_definitions = jsonencode([
    {
      name = "app-ecs"
      # La primera liberación instala la imagen real.
      image                  = "${aws_ecr_repository.app_ecs.repository_url}:bootstrap"
      essential              = true
      readonlyRootFilesystem = true
      portMappings = [
        {
          containerPort = 3000
          hostPort      = 3000
          protocol      = "tcp"
        }
      ]
      environment = [
        { name = "PORT", value = "3000" },
        { name = "APP_ENV", value = local.app_env },
        { name = "BASE_PATH", value = "" },
        { name = "DEPLOY_REF", value = "rel-62ee8d" }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.ecs.name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "ecs"
        }
      }
    }
  ])
}

resource "aws_ecs_service" "app_ecs" {
  name            = "app-ecs-service${local.resource_suffix}"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.app_ecs.arn
  desired_count   = var.ecs_desired_count
  launch_type     = "FARGATE"

  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  network_configuration {
    subnets          = aws_subnet.private[*].id
    security_groups  = [aws_security_group.ecs_tasks_sg.id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.ecs.arn
    container_name   = "app-ecs"
    container_port   = 3000
  }

  depends_on = [
    aws_lb_listener_rule.ecs_routes,
    aws_lb_listener_rule.ecs_health,
    aws_vpc_endpoint.ecr_and_logs,
    aws_vpc_endpoint.s3
  ]

  # Evita que Terraform revierta la revisión publicada por CodePipeline.
  lifecycle {
    ignore_changes = [task_definition]
  }
}

resource "aws_ecr_lifecycle_policy" "app_ecs" {
  repository = aws_ecr_repository.app_ecs.name
  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Mantener solo las ultimas 10 imagenes para control de costos y limpieza"
      selection = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        countNumber = 10
      }
      action = { type = "expire" }
    }]
  })
}
