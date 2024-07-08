# DynamoDB table for storing weather data
resource "aws_dynamodb_table" "weather_data" {
  name         = "HistoricalWeatherData"
  billing_mode = "PAY_PER_REQUEST"

  attribute {
    name = "property_id"
    type = "N"
  }

  attribute {
    name = "date"
    type = "S"
  }

  hash_key = "property_id"
  range_key = "date"
}

# SQS Queue for receiving weather data requests
resource "aws_sqs_queue" "weather_requests_queue" {
  name = "WeatherRequestsQueue"
}

# IAM role for Lambda function execution
resource "aws_iam_role" "lambda_exec" {
  name = "lambda_exec_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Action    = "sts:AssumeRole",
      Effect    = "Allow",
      Principal = {
        Service = "lambda.amazonaws.com"
      }
    }]
  })
}

# IAM policy for Lambda function to access DynamoDB and SQS
resource "aws_iam_policy" "lambda_policy" {
  name        = "lambda_policy"
  description = "IAM policy for Lambda execution"

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = [
          "dynamodb:PutItem",
          "dynamodb:UpdateItem",
          "dynamodb:GetItem",
          "dynamodb:BatchWriteItem"
        ],
        Resource = aws_dynamodb_table.weather_data.arn
      },
      {
        Effect = "Allow",
        Action = [
          "sqs:ReceiveMessage",
          "sqs:DeleteMessage",
          "sqs:GetQueueAttributes",
          "sqs:SendMessage"
        ],
        Resource = aws_sqs_queue.weather_requests_queue.arn
      }
    ]
  })
}

# IAM policy for Lambda to write logs to CloudWatch
resource "aws_iam_policy" "lambda_cloudwatch_policy" {
  name        = "LambdaCloudWatchPolicy"
  description = "IAM policy for Lambda to write logs to CloudWatch"

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect   = "Allow",
        Action   = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ],
        Resource = "arn:aws:logs:*:*:*"
      }
    ]
  })
}

# Attach CloudWatch policy to Lambda execution role
resource "aws_iam_role_policy_attachment" "lambda_cloudwatch_attach" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = aws_iam_policy.lambda_cloudwatch_policy.arn
}

# Attach DynamoDB and SQS policies to Lambda execution role
resource "aws_iam_role_policy_attachment" "lambda_policy_attachment" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = aws_iam_policy.lambda_policy.arn
}

# Lambda function for processing weather data
resource "aws_lambda_function" "weather_lambda" {
  filename         = "${path.module}/lambda-code/lambda_function.zip"
  function_name    = "weather_lambda"
  role             = aws_iam_role.lambda_exec.arn
  handler          = "lambda_function.lambda_handler"
  source_code_hash = filebase64sha256("${path.module}/lambda-code/lambda_function.zip")
  runtime          = "python3.12"

  environment {
    variables = {
      DYNAMODB_TABLE = aws_dynamodb_table.weather_data.name
      SQS_QUEUE_URL  = aws_sqs_queue.weather_requests_queue.id
    }
  }

  # Attach Lambda function to existing CloudWatch log group
  tracing_config {
    mode = "PassThrough"
  }

  depends_on = [
    aws_iam_role_policy_attachment.lambda_cloudwatch_attach,
    aws_iam_role_policy_attachment.lambda_policy_attachment
  ]
}

# CloudWatch log group for Lambda function
resource "aws_cloudwatch_log_group" "lambda_log_group" {
  name              = "/aws/lambda/weather_lambda"
  retention_in_days = 30  # Adjust retention period as per your requirement
}

# SQS trigger for Lambda function
resource "aws_lambda_event_source_mapping" "sqs_event_source" {
  event_source_arn = aws_sqs_queue.weather_requests_queue.arn
  function_name    = aws_lambda_function.weather_lambda.function_name
  batch_size       = 10  # Adjust batch size as per your requirement
}
