variable "aws_region" {
  default = "us-west-2"
}

variable "github_repo_id" {
  description = "Formato: usuario/nombre-repo en GitHub"
  type        = string
  default     = "antonio-pacheco-dez/examen-devops-aws"
}

variable "ecs_desired_count" {
  description = "Cantidad de tareas ECS; usa 0 al crear el servicio antes de publicar la primera imagen."
  type        = number
  default     = 1

  validation {
    condition     = var.ecs_desired_count >= 0 && floor(var.ecs_desired_count) == var.ecs_desired_count
    error_message = "ecs_desired_count debe ser un entero mayor o igual que cero."
  }
}

variable "alb_certificate_arn" {
  description = "ARN de un certificado ACM válido en la región del ALB. Si se omite, el ALB conserva HTTP."
  type        = string
  default     = null
  nullable    = true
}

variable "alb_domain_name" {
  description = "Dominio DNS cubierto por el certificado ACM; se usa como URL pública HTTPS."
  type        = string
  default     = null
  nullable    = true
}
