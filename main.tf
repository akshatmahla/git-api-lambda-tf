variable "lambda_function_name" {
  default = "sendEnquiryLambda"
}
variable "template_name" {
  type = string
}
variable "MAIL_FROM" {
    type = string
}
variable "MAIL_TO" {
  type = string
}
variable "my_region" {
  type = string
}
variable "my_account_id" {
  type = string
}
resource "aws_iam_role" "iam_for_lambda" {
  name = "iam_for_lambda"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "lambda.amazonaws.com"
      },
      "Effect": "Allow",
      "Sid": ""
    }
  ]
}
EOF
}
resource "aws_lambda_function" "test_lambda" {
  filename      = "lambda.zip"
  function_name = var.lambda_function_name
  role          = aws_iam_role.iam_for_lambda.arn
  handler       = "index.handler"

  # The filebase64sha256() function is available in Terraform 0.11.12 and later
  # For Terraform 0.11.11 and earlier, use the base64sha256() function and the file() function:
  # source_code_hash = "${base64sha256(file("lambda_function_payload.zip"))}"
  source_code_hash = filebase64sha256("lambda.zip")

  runtime = "nodejs16.x"
  timeout = 10
  environment {
    variables = {
      MAIL_FROM = var.MAIL_FROM,
      MAIL_TO = var.MAIL_TO,
      TEMPLATE_NAME = var.template_name
    }
  }

  # ... other configuration ...
  depends_on = [
    aws_iam_role_policy_attachment.lambda_logs,
    aws_cloudwatch_log_group.example,
  ]
}

# This is to optionally manage the CloudWatch Log Group for the Lambda Function.
# If skipping this resource configuration, also add "logs:CreateLogGroup" to the IAM policy below.
resource "aws_cloudwatch_log_group" "example" {
  name              = "/aws/lambda/${var.lambda_function_name}"
  retention_in_days = 14
}

# See also the following AWS managed policy: AWSLambdaBasicExecutionRole
resource "aws_iam_policy" "lambda_logging" {
  name        = "lambda_logging"
  path        = "/"
  description = "IAM policy for logging and SES from a lambda"

  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": [
        "ses:SendEmail",
        "ses:SendTemplatedEmail",
        "logs:CreateLogStream",
        "ses:SendRawEmail",
        "logs:CreateLogGroup",
        "logs:PutLogEvents"
      ],
      "Resource": "*",
      "Effect": "Allow"
    }
  ]
}
EOF
}

resource "aws_iam_role_policy_attachment" "lambda_logs" {
  role       = aws_iam_role.iam_for_lambda.name
  policy_arn = aws_iam_policy.lambda_logging.arn
}

resource "aws_ses_template" "MyTemplate" {
  name    = var.template_name
  subject = "Enquiry from, {{name}}!"
  html    = "<html><head><style> table { font-family: Arial, Helvetica, sans-serif; border-collapse: collapse; width: 100%; margin: 20px; } td, th { border: 1px solid #ddd; padding: 8px; } tr:nth-child(even) { background-color: #f2f2f2; } tr:hover { background-color: #ddd; } th { padding-top: 12px; padding-bottom: 12px; text-align: left; background-color: orange; color: white; } </style></head> <body> <h1>Enquiry Details:</h1> <table> <tbody> <tr> <th>Field</th> <th>Value</th> </tr> <tr> <td>Name</td> <td>{{name}}</td> </tr> <tr> <td>Email</td> <td>{{email}}</td> </tr> <tr> <td>Mobile No.</td> <td>{{mobile}}</td> </tr> <tr> <td>Requirement</td> <td>{{requirement}}</td> </tr> <tr> <td>Product</td> <td>{{product}}</td> </tr> <tr> <td>Purpose</td> <td>{{purpose}}</td> </tr> <tr> <td>Quantity</td> <td>{{quantity}}</td> </tr> </tbody> </table> </body></html>"
  text    = "Hello {{name}}"
}

# API Gateway
resource "aws_api_gateway_rest_api" "api" {
  name = "EnquireApiMail"
  endpoint_configuration {
    types = ["REGIONAL"]
  }
   body = jsonencode({
    openapi = "3.0.1"
    info = {
      title   = "example"
      version = "1.0"
    }
    paths = {
      "/" = {
        post = {
          x-amazon-apigateway-integration = {
            httpMethod           = "POST"
            payloadFormatVersion = "1.0"
            type                 = "AWS"
            uri                  = "${aws_lambda_function.test_lambda.invoke_arn}"
          }
        }
      }
    }
  })
  
}

# resource "aws_api_gateway_resource" "resource" {
#   path_part   = "sendEnquiry"
#   parent_id   = aws_api_gateway_rest_api.api.root_resource_id
#   rest_api_id = aws_api_gateway_rest_api.api.id
# }

# resource "aws_api_gateway_method" "method" {
#   rest_api_id   = aws_api_gateway_rest_api.api.id
#   resource_id   = aws_api_gateway_rest_api.api.root_resource_id
#   http_method   = "POST"
#   authorization = "NONE"
# }

# resource "aws_api_gateway_integration" "integration" {
#   rest_api_id             = aws_api_gateway_rest_api.api.id
#   resource_id             = aws_api_gateway_rest_api.api.root_resource_id
#   http_method             = aws_api_gateway_method.method.http_method
#   integration_http_method = "POST"
#   type                    = "AWS"
#   uri                     = aws_lambda_function.test_lambda.invoke_arn
# }

# Lambda
resource "aws_lambda_permission" "apigw_lambda" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.test_lambda.function_name
  principal     = "apigateway.amazonaws.com"

  # More: http://docs.aws.amazon.com/apigateway/latest/developerguide/api-gateway-control-access-using-iam-policies-to-invoke-api.html
  source_arn = "arn:aws:execute-api:${var.my_region}:${var.my_account_id}:${aws_api_gateway_rest_api.api.id}/*/POST/"
}
resource "aws_api_gateway_method_response" "response_200" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  resource_id = aws_api_gateway_rest_api.api.root_resource_id
  http_method = "POST"
  status_code = "200"
  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = true,
    "method.response.header.Access-Control-Allow-Origin" = true
  }
  
}

resource "aws_api_gateway_integration_response" "MyIntegrationResponse" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  resource_id = aws_api_gateway_rest_api.api.root_resource_id
  http_method = "POST"
  status_code = aws_api_gateway_method_response.response_200.status_code

  response_parameters = { 
    "method.response.header.Access-Control-Allow-Headers" = "'Origin, X-Requested-With, Content-Type, Accept'",
    "method.response.header.Access-Control-Allow-Origin" = "'*'"
   }
  
}

resource "aws_api_gateway_deployment" "example" {
  rest_api_id = aws_api_gateway_rest_api.api.id

  triggers = {
    redeployment = sha1(jsonencode(aws_api_gateway_rest_api.api.body))
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_api_gateway_stage" "example" {
  deployment_id = aws_api_gateway_deployment.example.id
  rest_api_id   = aws_api_gateway_rest_api.api.id
  stage_name    = "dev"
}

output "invoke_URL" {
  value = aws_api_gateway_stage.example.invoke_url
}