resource "aws_lb" "main" {
  name                       = "${local.name_prefix}-alb"
  internal                   = false
  load_balancer_type         = "application"
  security_groups            = [aws_security_group.alb_sg.id]
  subnets                    = aws_subnet.public[*].id
  drop_invalid_header_fields = true # Hardening de cabeceras HTTP
}

# Distribuye el tráfico hacia las tareas de ECS.
resource "aws_lb_target_group" "ecs" {
  name        = "tg-app-ecs${local.resource_suffix}"
  port        = 3000
  protocol    = "HTTP"
  vpc_id      = aws_vpc.main.id
  target_type = "ip"

  health_check {
    enabled             = true
    path                = "/health"
    matcher             = "200"
    interval            = 15
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }
}

# Envía solicitudes compatibles al handler de Lambda.
resource "aws_lb_target_group" "lambda" {
  name        = "tg-app-lambda${local.resource_suffix}"
  target_type = "lambda"

  health_check {
    enabled             = true
    path                = "/health"
    matcher             = "200"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.main.arn
  port              = 80
  protocol          = "HTTP"

  # Redirige a HTTPS cuando se configura un certificado.
  default_action {
    type = var.alb_certificate_arn == null ? "fixed-response" : "redirect"

    dynamic "fixed_response" {
      for_each = var.alb_certificate_arn == null ? [1] : []
      content {
        content_type = "application/json"
        message_body = "{\"error\":\"Ruta no autorizada\"}"
        status_code  = "404"
      }
    }

    dynamic "redirect" {
      for_each = var.alb_certificate_arn == null ? [] : [1]
      content {
        port        = "443"
        protocol    = "HTTPS"
        status_code = "HTTP_301"
      }
    }
  }
}

# El listener HTTPS requiere un certificado ACM válido.
resource "aws_lb_listener" "https" {
  count = var.alb_certificate_arn == null ? 0 : 1

  load_balancer_arn = aws_lb.main.arn
  port              = 443
  protocol          = "HTTPS"
  certificate_arn   = var.alb_certificate_arn
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"

  default_action {
    type = "fixed-response"

    fixed_response {
      content_type = "application/json"
      message_body = "{\"error\":\"Ruta no autorizada\"}"
      status_code  = "404"
    }
  }

  lifecycle {
    precondition {
      condition     = var.alb_domain_name != null && trimspace(var.alb_domain_name) != ""
      error_message = "Configura alb_domain_name con un dominio cubierto por el certificado ACM cuando habilites HTTPS."
    }
  }
}

locals {
  alb_application_listener_arn = var.alb_certificate_arn == null ? aws_lb_listener.http.arn : aws_lb_listener.https[0].arn
}

# Envía las rutas de catálogo a ECS.
resource "aws_lb_listener_rule" "ecs_routes" {
  listener_arn = local.alb_application_listener_arn
  priority     = 10

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.ecs.arn
  }

  condition {
    path_pattern {
      values = [
        "/api/clientes",
        "/api/clientes/*",
        "/api/productos",
        "/api/productos/*"
      ]
    }
  }
}

resource "aws_lb_listener_rule" "ecs_info_routes" {
  listener_arn = local.alb_application_listener_arn
  priority     = 11

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.ecs.arn
  }

  condition {
    path_pattern {
      values = ["/api/info", "/api/info/*"]
    }
  }
}

# Envía pedidos y reportes a Lambda.
resource "aws_lb_listener_rule" "lambda_routes" {
  listener_arn = local.alb_application_listener_arn
  priority     = 20

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.lambda.arn
  }

  condition {
    path_pattern {
      values = [
        "/api/pedidos",
        "/api/pedidos/*",
        "/api/reportes",
        "/api/reportes/*"
      ]
    }
  }
}

# Permite comprobar la salud de Lambda desde el ALB.
resource "aws_lb_listener_rule" "lambda_health" {
  listener_arn = local.alb_application_listener_arn
  priority     = 30

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.lambda.arn
  }

  condition {
    path_pattern {
      values = ["/health"]
    }
  }

  condition {
    query_string {
      key   = "service"
      value = "lambda"
    }
  }
}

# Envía la comprobación general de salud a ECS.
resource "aws_lb_listener_rule" "ecs_health" {
  listener_arn = local.alb_application_listener_arn
  priority     = 40

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.ecs.arn
  }

  condition {
    path_pattern {
      values = ["/health"]
    }
  }
}
