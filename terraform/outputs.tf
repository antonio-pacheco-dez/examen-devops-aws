output "app_ecs_pipeline_name" {
  description = "Nombre del pipeline que construye y despliega la aplicación ECS."
  value       = aws_codepipeline.ecs_pipeline.name
}

output "app_lambda_pipeline_name" {
  description = "Nombre del pipeline que empaqueta y despliega la aplicación Lambda."
  value       = aws_codepipeline.lambda_pipeline.name
}

output "ecs_cluster_name" {
  description = "Nombre del clúster ECS del workspace actual."
  value       = aws_ecs_cluster.main.name
}

output "ecs_service_name" {
  description = "Nombre del servicio ECS del workspace actual."
  value       = aws_ecs_service.app_ecs.name
}

output "ecs_target_group_arn" {
  description = "ARN del target group ECS detrás del ALB."
  value       = aws_lb_target_group.ecs.arn
}

output "lambda_function_name" {
  description = "Nombre de la función Lambda del workspace actual."
  value       = aws_lambda_function.app_lambda.function_name
}

output "lambda_target_group_arn" {
  description = "ARN del target group Lambda detrás del ALB."
  value       = aws_lb_target_group.lambda.arn
}
