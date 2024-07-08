output "lambda_function_name" {
  value = aws_lambda_function.weather_lambda.function_name
}

output "sqs_queue_url" {
  value = aws_sqs_queue.weather_requests_queue.url
}

output "dynamodb_table_name" {
  value = aws_dynamodb_table.weather_data.name
}