data "aws_lambda_function" "gcl_jira_issue" {
  function_name = var.gcl_jira_issue_lambda_name
}

data "aws_lambda_function" "gcl_jira_transitions" {
  function_name = var.gcl_jira_transitions_lambda_name
}

data "aws_lambda_function" "gcl_turbot_accounts" {
  function_name = var.gcl_turbot_accounts_lambda_name
}

data "aws_lambda_function" "gcl_turbot_joinlab" {
  function_name = var.gcl_turbot_joinlab_lambda_name
}

data "aws_lambda_function" "gcl_search_snow_id" {
  function_name = var.gcl_search_snow_id_name
}

resource "aws_iam_role" "api_gateway_role" {
  name                  = var.api_gateway_role_name
  force_detach_policies = true
  assume_role_policy    = jsonencode({
    Version   = "2012-10-17"
    Statement = [
      {
        Sid    = ""
        Effect = "Allow"
        Action = "sts:AssumeRole"
        Principal = {
          Service = "apigateway.amazonaws.com"
        }
      },
    ]
  })
}

resource "aws_iam_role_policy" "api_gateway_role_policy" {
  name   = var.api_gateway_policy_name
  role   = aws_iam_role.api_gateway_role.id
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = [
          "s3:Get*",
          "s3:List*"
          ],
        Resource = [
          var.s3_bucket_arn,
          "${var.s3_bucket_arn}/*"
          ]
      },
      {
        Effect = "Allow",
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:DescribeLogGroups",
          "logs:DescribeLogStreams",
          "logs:PutLogEvents",
          "logs:GetLogEvents",
          "logs:FilterLogEvents"
        ],
        Resource = "*"
      }
    ]
  })
}

resource "aws_api_gateway_rest_api" "api_gateway" {
  name        = var.api_gateway_name
  description = var.api_gateway_description

  endpoint_configuration {
    types = ["PRIVATE"]
  }

  binary_media_types = [
    "image/vnd.microsoft.icon"
  ]
}

resource "aws_api_gateway_rest_api_policy" "api_gateway_resource_policy" {
  rest_api_id = aws_api_gateway_rest_api.api_gateway.id

  policy = jsonencode({
    Version: "2012-10-17",
    Statement: [
      {
        Sid       = ""
        Effect    = "Allow",
        Principal = { 
          AWS     = "*"
          },
        Action    = "execute-api:Invoke",
        Resource  =  "*"
      }
    ]
  })
}

resource "aws_api_gateway_method" "root_any" {
  rest_api_id   = aws_api_gateway_rest_api.api_gateway.id
  resource_id   = aws_api_gateway_rest_api.api_gateway.root_resource_id
  http_method   = "ANY"
  authorization = "NONE"

  request_parameters = {
    "method.request.header.Content-Disposition" = false
    "method.request.header.Content-Type"        = false
  }
}

resource "aws_api_gateway_integration" "root_s3_integration" {
  rest_api_id             = aws_api_gateway_rest_api.api_gateway.id
  resource_id             = aws_api_gateway_rest_api.api_gateway.root_resource_id
  http_method             = aws_api_gateway_method.root_any.http_method
  type                    = "AWS"
  credentials             = aws_iam_role.api_gateway_role.arn
  integration_http_method = "ANY"
  uri                     = "arn:aws:apigateway:us-east-1:s3:path/${var.s3_bucket_name}/index.html"

  request_parameters = {
    "integration.request.header.Content-Disposition" = "method.request.header.Content-Disposition"
    "integration.request.header.Content-Type"        = "method.request.header.Content-Type"
  }

  passthrough_behavior = "WHEN_NO_MATCH"
}

resource "aws_api_gateway_method_response" "root_response_200" {
  depends_on  = [aws_api_gateway_integration.root_s3_integration]
  rest_api_id = aws_api_gateway_rest_api.api_gateway.id
  resource_id = aws_api_gateway_rest_api.api_gateway.root_resource_id
  http_method = aws_api_gateway_method.root_any.http_method
  status_code = "200"

  response_models = {
    "application/json" = "Empty"
  }

  response_parameters = {
    "method.response.header.Content-Disposition" = false
    "method.response.header.Content-Type"        = false
  }
}

resource "aws_api_gateway_integration_response" "root_s3_integration_response" {
  depends_on  = [
    aws_api_gateway_integration.root_s3_integration,
    aws_api_gateway_method_response.root_response_200
  ]
  rest_api_id = aws_api_gateway_rest_api.api_gateway.id
  resource_id = aws_api_gateway_rest_api.api_gateway.root_resource_id
  http_method = aws_api_gateway_method.root_any.http_method
  status_code = "200"

  response_parameters  = {
    "method.response.header.Content-Disposition" = "integration.response.header.Content-Disposition"
    "method.response.header.Content-Type"        = "integration.response.header.Content-Type"
  }
}


### /v1 path ####
resource "aws_api_gateway_resource" "v1_path" {
  rest_api_id = aws_api_gateway_rest_api.api_gateway.id
  parent_id   = aws_api_gateway_rest_api.api_gateway.root_resource_id
  path_part   = "v1"
}

resource "aws_api_gateway_method" "v1_options" {
  depends_on    = [aws_api_gateway_resource.v1_path]
  rest_api_id   = aws_api_gateway_rest_api.api_gateway.id
  resource_id   = aws_api_gateway_resource.v1_path.id
  http_method   = "OPTIONS"
  authorization = "NONE"

  request_parameters = {
    "method.request.path.proxy" = true
  }
}

resource "aws_api_gateway_integration" "v1_mock_integration" {
  depends_on           = [aws_api_gateway_method.v1_options]
  rest_api_id          = aws_api_gateway_rest_api.api_gateway.id
  resource_id          = aws_api_gateway_resource.v1_path.id
  http_method          = aws_api_gateway_method.v1_options.http_method
  type                 = "MOCK"
  passthrough_behavior = "WHEN_NO_MATCH"

  request_templates = {
     "application/json" = jsonencode({
       statusCode = 200
       }
     )
  }
}

resource "aws_api_gateway_method_response" "v1_mock_response_200" {
  depends_on  = [aws_api_gateway_integration.v1_mock_integration]
  rest_api_id = aws_api_gateway_rest_api.api_gateway.id
  resource_id = aws_api_gateway_resource.v1_path.id
  http_method = aws_api_gateway_method.v1_options.http_method
  status_code = "200"

  response_models = {
    "application/json" = "Empty"
  }

  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = false
    "method.response.header.Access-Control-Allow-Methods" = false
    "method.response.header.Access-Control-Allow-Origin" = false
  }
}

resource "aws_api_gateway_integration_response" "v1_mock_integration_response" {
  depends_on  = [
    aws_api_gateway_integration.v1_mock_integration,
    aws_api_gateway_method_response.v1_mock_response_200
  ]
  rest_api_id = aws_api_gateway_rest_api.api_gateway.id
  resource_id = aws_api_gateway_resource.v1_path.id
  http_method = aws_api_gateway_method.v1_options.http_method
  status_code = "200"

  response_parameters  = {
    "method.response.header.Access-Control-Allow-Methods" = "'DELETE,GET,HEAD,OPTIONS,PATCH,POST,PUT'"
    "method.response.header.Access-Control-Allow-Headers" = "'Content-Type,Authorization,X-Amz-Date,X-Api-Key,X-Amz-Security-Token'"
    "method.response.header.Access-Control-Allow-Origin"  = "'*'"
  }
}

### /snow path ####
resource "aws_api_gateway_resource" "snow_path" {
  rest_api_id = aws_api_gateway_rest_api.api_gateway.id
  parent_id   = aws_api_gateway_resource.v1_path.id
  path_part   = "snow"
}

### /snow/{id} path ####
resource "aws_api_gateway_resource" "snow_id_path" {
  rest_api_id = aws_api_gateway_rest_api.api_gateway.id
  parent_id   = aws_api_gateway_resource.snow_path.id
  path_part   = "{id}"
}

### /snow/{id} get ####
resource "aws_api_gateway_method" "snow_id_method_request_get" {
  rest_api_id   = aws_api_gateway_rest_api.api_gateway.id
  resource_id   = aws_api_gateway_resource.snow_id_path.id
  http_method   = "GET"
  authorization = "NONE"
  request_parameters = {
    "method.request.path.id" = true
  }
}

resource "aws_api_gateway_integration" "snow_id_integration_request_get" {
  rest_api_id             = aws_api_gateway_rest_api.api_gateway.id
  resource_id             = aws_api_gateway_resource.snow_id_path.id
  http_method             = aws_api_gateway_method.snow_id_method_request_get.http_method
  type                    = "AWS_PROXY"
  integration_http_method = "POST"
  uri                     = "arn:aws:apigateway:${var.region}:lambda:path/2015-03-31/functions/${data.aws_lambda_function.gcl_search_snow_id.arn}/invocations"
}

resource "aws_api_gateway_method_response" "snow_id_method_response_get_200" {
  rest_api_id = aws_api_gateway_rest_api.api_gateway.id
  resource_id = aws_api_gateway_resource.snow_id_path.id
  http_method = aws_api_gateway_method.snow_id_method_request_get.http_method
  status_code = "200"
}

resource "aws_api_gateway_method" "snow_id_options" {
  depends_on    = [aws_api_gateway_resource.snow_id_path]
  rest_api_id   = aws_api_gateway_rest_api.api_gateway.id
  resource_id   = aws_api_gateway_resource.snow_id_path.id
  http_method   = "OPTIONS"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "snow_id_integration_request_options" {
  depends_on           = [aws_api_gateway_method.snow_id_options]
  rest_api_id          = aws_api_gateway_rest_api.api_gateway.id
  resource_id          = aws_api_gateway_resource.snow_id_path.id
  http_method          = aws_api_gateway_method.snow_id_options.http_method
  type                 = "MOCK"
  passthrough_behavior = "WHEN_NO_MATCH"
  request_templates    = {
     "application/json" = jsonencode({
       statusCode = 200
       }
     )
  }
}

resource "aws_api_gateway_method_response" "snow_id_method_response_options_200" {
  depends_on  = [aws_api_gateway_integration.snow_id_integration_request_options]
  rest_api_id = aws_api_gateway_rest_api.api_gateway.id
  resource_id = aws_api_gateway_resource.snow_id_path.id
  http_method = aws_api_gateway_method.snow_id_options.http_method
  status_code = "200"

  response_models = {
    "application/json" = "Empty"
  }

  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = false
    "method.response.header.Access-Control-Allow-Methods" = false
    "method.response.header.Access-Control-Allow-Origin" = false
  }
}

resource "aws_api_gateway_integration_response" "snow_id_integration_response_options" {
  depends_on  = [
    aws_api_gateway_integration.snow_id_integration_request_options,
    aws_api_gateway_method_response.snow_id_method_response_options_200
  ]
  rest_api_id = aws_api_gateway_rest_api.api_gateway.id
  resource_id = aws_api_gateway_resource.snow_id_path.id
  http_method = aws_api_gateway_method.snow_id_options.http_method
  status_code = "200"

  response_parameters  = {
    "method.response.header.Access-Control-Allow-Methods" = "'DELETE,GET,HEAD,OPTIONS,PATCH,POST,PUT'"
    "method.response.header.Access-Control-Allow-Headers" = "'Content-Type,Authorization,X-Amz-Date,X-Api-Key,X-Amz-Security-Token'"
    "method.response.header.Access-Control-Allow-Origin" = "'*'"
  }
}

### /jira path ####
resource "aws_api_gateway_resource" "jira_path" {
  rest_api_id = aws_api_gateway_rest_api.api_gateway.id
  parent_id   = aws_api_gateway_resource.v1_path.id
  path_part   = "jira"
}

### /jira/issue path ####
resource "aws_api_gateway_resource" "jira_issue_path" {
  rest_api_id = aws_api_gateway_rest_api.api_gateway.id
  parent_id   = aws_api_gateway_resource.jira_path.id
  path_part   = "issue"
}

resource "aws_api_gateway_model" "jira_request_model" {
  rest_api_id  = aws_api_gateway_rest_api.api_gateway.id
  name         = "jiraRequest"
  description  = "a JSON schema for Jira request"
  content_type = "application/json"
  schema       = <<EOF
{
  "$schema": "http://json-schema.org/draft-04/schema#",
  "type": "object",
  "properties": {
    "fields": {
      "type": "object",
      "properties": {
        "project": {
          "type": "object",
          "properties": {
            "key": {
              "type": "string"
            }
          },
          "required": [
            "key"
          ]
        },
        "summary": {
          "type": "string"
        },
        "description": {
          "type": "string"
        },
        "issuetype": {
          "type": "object",
          "properties": {
            "name": {
              "type": "string"
            }
          },
          "required": [
            "name"
          ]
        },
        "components": {
          "type": "array",
          "items": [
            {
              "type": "object",
              "properties": {
                "id": {
                  "type": "string"
                }
              },
              "required": [
                "id"
              ]
            }
          ]
        },
        "reporter": {
          "type": "object",
          "properties": {
            "name": {
              "type": "string"
            }
          },
          "required": [
            "name"
          ]
        },
        "labels": {
          "type": "array",
          "items": [
            {
              "type": "string"
            },
            {
              "type": "string"
            }
          ]
        }
      },
      "required": [
        "project",
        "summary",
        "description",
        "issuetype",
        "components",
        "reporter",
        "labels"
      ]
    }
  },
  "required": [
    "fields"
  ]
}
EOF
}

resource "aws_api_gateway_model" "jira_response_model" {
  rest_api_id  = aws_api_gateway_rest_api.api_gateway.id
  name         = "jiraResponse"
  description  = "a JSON schema for Jira response"
  content_type = "application/json"
  schema       = <<EOF
{
  "type" : "object",
  "required" : [ "browseUrl", "id", "key", "self" ],
  "properties" : {
    "id" : {
      "type" : "string"
    },
    "key" : {
      "type" : "string"
    },
    "self" : {
      "type" : "string"
    },
    "browseUrl" : {
      "type" : "string"
    }
  }
}
EOF
}

### /jira/issue post ####
resource "aws_api_gateway_method" "jira_issue_method_request_post" {
  depends_on  = [aws_api_gateway_model.jira_request_model]
  rest_api_id   = aws_api_gateway_rest_api.api_gateway.id
  resource_id   = aws_api_gateway_resource.jira_issue_path.id
  http_method   = "POST"
  authorization = "NONE"

  request_models = {
    "application/json" = "jiraRequest"
    }
}

resource "aws_api_gateway_integration" "jira_issue_integration_request_post" {
  rest_api_id             = aws_api_gateway_rest_api.api_gateway.id
  resource_id             = aws_api_gateway_resource.jira_issue_path.id
  http_method             = aws_api_gateway_method.jira_issue_method_request_post.http_method
  type                    = "AWS"
  content_handling        = "CONVERT_TO_TEXT"
  integration_http_method = "POST"
  uri                     = "arn:aws:apigateway:${var.region}:lambda:path/2015-03-31/functions/${data.aws_lambda_function.gcl_jira_issue.arn}/invocations"
  passthrough_behavior    = "WHEN_NO_TEMPLATES"

  request_templates = {
    "application/json" = <<EOF
{"body":"$util.escapeJavaScript($input.json('$')).replaceAll("\\'","'")"}
EOF
  }
}

resource "aws_api_gateway_method_response" "jira_issue_method_response_post_200" {
  depends_on  = [
    aws_api_gateway_integration.jira_issue_integration_request_post,
    aws_api_gateway_model.jira_response_model
  ]
  rest_api_id = aws_api_gateway_rest_api.api_gateway.id
  resource_id = aws_api_gateway_resource.jira_issue_path.id
  http_method = aws_api_gateway_method.jira_issue_method_request_post.http_method
  status_code = "200"

  response_parameters = {
    "method.response.header.Access-Control-Allow-Origin" = false
  }
    response_models = {
    "application/json" = "jiraResponse"
  }
}

resource "aws_api_gateway_method_response" "jira_issue_method_response_post_201" {
  depends_on  = [
    aws_api_gateway_integration.jira_issue_integration_request_post,
    aws_api_gateway_model.jira_response_model
  ]
  rest_api_id = aws_api_gateway_rest_api.api_gateway.id
  resource_id = aws_api_gateway_resource.jira_issue_path.id
  http_method = aws_api_gateway_method.jira_issue_method_request_post.http_method
  status_code = "201"

  response_models = {
    "application/json" = "jiraResponse"
    }
}

resource "aws_api_gateway_integration_response" "jira_issue_integration_response_post" {
  depends_on  = [
    aws_api_gateway_integration.jira_issue_integration_request_post,
    aws_api_gateway_method_response.jira_issue_method_response_post_200
  ]
  rest_api_id = aws_api_gateway_rest_api.api_gateway.id
  resource_id = aws_api_gateway_resource.jira_issue_path.id
  http_method = aws_api_gateway_method.jira_issue_method_request_post.http_method
  status_code = "200"

  response_parameters  = {
    "method.response.header.Access-Control-Allow-Origin" = "'*'"
  }
}

### /jira/issue options ####
resource "aws_api_gateway_method" "jira_issue_method_request_options" {
  depends_on    = [aws_api_gateway_resource.jira_issue_path]
  rest_api_id   = aws_api_gateway_rest_api.api_gateway.id
  resource_id   = aws_api_gateway_resource.jira_issue_path.id
  http_method   = "OPTIONS"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "jira_issue_integration_request_options" {
  depends_on           = [aws_api_gateway_method.jira_issue_method_request_options]
  rest_api_id          = aws_api_gateway_rest_api.api_gateway.id
  resource_id          = aws_api_gateway_resource.jira_issue_path.id
  http_method          = aws_api_gateway_method.jira_issue_method_request_options.http_method
  type                 = "MOCK"
  passthrough_behavior = "WHEN_NO_MATCH"
  request_templates    = {
     "application/json" = jsonencode({
       statusCode = 200
       }
     )
  }
}

resource "aws_api_gateway_method_response" "jira_issue_method_response_options_200" {
  depends_on  = [aws_api_gateway_integration.jira_issue_integration_request_options]
  rest_api_id = aws_api_gateway_rest_api.api_gateway.id
  resource_id = aws_api_gateway_resource.jira_issue_path.id
  http_method = aws_api_gateway_method.jira_issue_method_request_options.http_method
  status_code = "200"

  response_models = {
    "application/json" = "Empty"
  }

  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = false
    "method.response.header.Access-Control-Allow-Methods" = false
    "method.response.header.Access-Control-Allow-Origin" = false
  }
}

resource "aws_api_gateway_integration_response" "jira_issue_integration_response_options" {
  depends_on  = [
    aws_api_gateway_integration.jira_issue_integration_request_options,
    aws_api_gateway_method_response.jira_issue_method_response_options_200
  ]
  rest_api_id = aws_api_gateway_rest_api.api_gateway.id
  resource_id = aws_api_gateway_resource.jira_issue_path.id
  http_method = aws_api_gateway_method.jira_issue_method_request_options.http_method
  status_code = "200"

  response_parameters  = {
    "method.response.header.Access-Control-Allow-Methods" = "'DELETE,GET,HEAD,OPTIONS,PATCH,POST,PUT'"
    "method.response.header.Access-Control-Allow-Headers" = "'Content-Type,Authorization,X-Amz-Date,X-Api-Key,X-Amz-Security-Token'"
    "method.response.header.Access-Control-Allow-Origin" = "'*'"
  }
}

### /jira/transitions path ####
resource "aws_api_gateway_resource" "jira_transitions_path" {
  rest_api_id = aws_api_gateway_rest_api.api_gateway.id
  parent_id   = aws_api_gateway_resource.jira_path.id
  path_part   = "transitions"
}

### /jira/transitions post ####

resource "aws_api_gateway_method" "jira_transitions_method_request_post" {
  rest_api_id   = aws_api_gateway_rest_api.api_gateway.id
  resource_id   = aws_api_gateway_resource.jira_transitions_path.id
  http_method   = "POST"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "jira_transitions_integration_request_post" {
  rest_api_id             = aws_api_gateway_rest_api.api_gateway.id
  resource_id             = aws_api_gateway_resource.jira_transitions_path.id
  http_method             = aws_api_gateway_method.jira_transitions_method_request_post.http_method
  type                    = "AWS"
  content_handling        = "CONVERT_TO_TEXT"
  integration_http_method = "POST"
  uri                     = "arn:aws:apigateway:${var.region}:lambda:path/2015-03-31/functions/${data.aws_lambda_function.gcl_jira_transitions.arn}/invocations"
  passthrough_behavior    = "WHEN_NO_TEMPLATES"

  request_templates = {
    "application/json" = <<EOF
{"body":"$util.escapeJavaScript($input.json('$')).replaceAll("\\'","'")"}
EOF
  }
}

resource "aws_api_gateway_method_response" "jira_transitions_method_response_200" {
  depends_on  = [aws_api_gateway_integration.jira_transitions_integration_request_post]
  rest_api_id = aws_api_gateway_rest_api.api_gateway.id
  resource_id = aws_api_gateway_resource.jira_transitions_path.id
  http_method = aws_api_gateway_method.jira_transitions_method_request_post.http_method
  status_code = "200"

  response_models = {
    "application/json" = "Empty"
  }
}

resource "aws_api_gateway_integration_response" "jira_transitions_integration_response" {
  depends_on  = [
    aws_api_gateway_integration.jira_transitions_integration_request_post,
    aws_api_gateway_method_response.jira_transitions_method_response_200
  ]
  rest_api_id = aws_api_gateway_rest_api.api_gateway.id
  resource_id = aws_api_gateway_resource.jira_transitions_path.id
  http_method = aws_api_gateway_method.jira_transitions_method_request_post.http_method
  status_code = "200"
}

### /jira/transitions options ####
resource "aws_api_gateway_method" "jira_transitions_method_request_options" {
  depends_on    = [aws_api_gateway_resource.jira_transitions_path]
  rest_api_id   = aws_api_gateway_rest_api.api_gateway.id
  resource_id   = aws_api_gateway_resource.jira_transitions_path.id
  http_method   = "OPTIONS"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "jira_transitions_integration_request_options" {
  depends_on           = [aws_api_gateway_method.jira_transitions_method_request_options]
  rest_api_id          = aws_api_gateway_rest_api.api_gateway.id
  resource_id          = aws_api_gateway_resource.jira_transitions_path.id
  http_method          = aws_api_gateway_method.jira_transitions_method_request_options.http_method
  type                 = "MOCK"
  passthrough_behavior = "WHEN_NO_MATCH"
  request_templates    = {
     "application/json" = jsonencode({
       statusCode = 200
       }
     )
  }
}

resource "aws_api_gateway_method_response" "jira_transitions_method_response_options_200" {
  depends_on  = [aws_api_gateway_integration.jira_transitions_integration_request_options]
  rest_api_id = aws_api_gateway_rest_api.api_gateway.id
  resource_id = aws_api_gateway_resource.jira_transitions_path.id
  http_method = aws_api_gateway_method.jira_transitions_method_request_options.http_method
  status_code = "200"

  response_models = {
    "application/json" = "Empty"
  }

  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = false
    "method.response.header.Access-Control-Allow-Methods" = false
    "method.response.header.Access-Control-Allow-Origin" = false
  }
}

resource "aws_api_gateway_integration_response" "jira_transitions_integration_response_options" {
  depends_on  = [
    aws_api_gateway_integration.jira_transitions_integration_request_options,
    aws_api_gateway_method_response.jira_transitions_method_response_options_200
  ]
  rest_api_id = aws_api_gateway_rest_api.api_gateway.id
  resource_id = aws_api_gateway_resource.jira_transitions_path.id
  http_method = aws_api_gateway_method.jira_transitions_method_request_options.http_method
  status_code = "200"

  response_parameters  = {
    "method.response.header.Access-Control-Allow-Methods" = "'DELETE,GET,HEAD,OPTIONS,PATCH,POST,PUT'"
    "method.response.header.Access-Control-Allow-Headers" = "'Content-Type,Authorization,X-Amz-Date,X-Api-Key,X-Amz-Security-Token'"
    "method.response.header.Access-Control-Allow-Origin" = "'*'"
  }
}

### /turbot path ####
resource "aws_api_gateway_resource" "turbot_path" {
  rest_api_id = aws_api_gateway_rest_api.api_gateway.id
  parent_id   = aws_api_gateway_resource.v1_path.id
  path_part   = "turbot"
}

### /turbot/accounts path ####
resource "aws_api_gateway_resource" "turbot_accounts_path" {
  rest_api_id = aws_api_gateway_rest_api.api_gateway.id
  parent_id   = aws_api_gateway_resource.turbot_path.id
  path_part   = "accounts"
}

### /turbot/accounts get ####
resource "aws_api_gateway_method" "turbot_accounts_method_request_get" {
  rest_api_id   = aws_api_gateway_rest_api.api_gateway.id
  resource_id   = aws_api_gateway_resource.turbot_accounts_path.id
  http_method   = "GET"
  authorization = "NONE"

  request_parameters = {
    "method.request.querystring.Content-Type" = false
    "method.request.querystring.Query"        = false
  }
}

resource "aws_api_gateway_integration" "turbot_accounts_integration_request_get" {
  rest_api_id             = aws_api_gateway_rest_api.api_gateway.id
  resource_id             = aws_api_gateway_resource.turbot_accounts_path.id
  http_method             = aws_api_gateway_method.turbot_accounts_method_request_get.http_method
  type                    = "AWS"
  content_handling        = "CONVERT_TO_TEXT"
  integration_http_method = "POST"
  uri                     = "arn:aws:apigateway:${var.region}:lambda:path/2015-03-31/functions/${data.aws_lambda_function.gcl_turbot_accounts.arn}/invocations"
  passthrough_behavior    = "WHEN_NO_TEMPLATES"

  request_templates = {
    "application/json" = jsonencode({
      meta = {
        path = "/",
        query = ""
        }
      }
    )
  }
}

resource "aws_api_gateway_method_response" "turbot_accounts_method_response_get_200" {
  depends_on  = [aws_api_gateway_integration.turbot_accounts_integration_request_get]
  rest_api_id = aws_api_gateway_rest_api.api_gateway.id
  resource_id = aws_api_gateway_resource.turbot_accounts_path.id
  http_method = aws_api_gateway_method.turbot_accounts_method_request_get.http_method
  status_code = "200"

  response_parameters = {
    "method.response.header.Access-Control-Allow-Origin" = false
  }
  response_models = {
    "application/json" = "Empty"
  }
}

resource "aws_api_gateway_integration_response" "turbot_accounts_integration_response_get" {
  depends_on  = [
    aws_api_gateway_integration.turbot_accounts_integration_request_get,
    aws_api_gateway_method_response.turbot_accounts_method_response_get_200
  ]
  rest_api_id = aws_api_gateway_rest_api.api_gateway.id
  resource_id = aws_api_gateway_resource.turbot_accounts_path.id
  http_method = aws_api_gateway_method.turbot_accounts_method_request_get.http_method
  status_code = "200"

  response_parameters  = {
    "method.response.header.Access-Control-Allow-Origin" = "'*'"
  }
}

### /turbot/accounts options ####
resource "aws_api_gateway_method" "turbot_accounts_method_request_options" {
  depends_on    = [aws_api_gateway_resource.turbot_accounts_path]
  rest_api_id   = aws_api_gateway_rest_api.api_gateway.id
  resource_id   = aws_api_gateway_resource.turbot_accounts_path.id
  http_method   = "OPTIONS"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "turbot_accounts_integration_request_options" {
  depends_on          = [aws_api_gateway_method.turbot_accounts_method_request_options]
  rest_api_id         = aws_api_gateway_rest_api.api_gateway.id
  resource_id         = aws_api_gateway_resource.turbot_accounts_path.id
  http_method         = aws_api_gateway_method.turbot_accounts_method_request_options.http_method
  type                = "MOCK"
  passthrough_behavior    = "WHEN_NO_MATCH"

  request_templates = {
     "application/json" = jsonencode({
       statusCode = 200
       }
     )
  }
}

resource "aws_api_gateway_method_response" "turbot_accounts_method_response_options_200" {
  depends_on  = [aws_api_gateway_integration.turbot_accounts_integration_request_options]
  rest_api_id = aws_api_gateway_rest_api.api_gateway.id
  resource_id = aws_api_gateway_resource.turbot_accounts_path.id
  http_method = aws_api_gateway_method.turbot_accounts_method_request_options.http_method
  status_code = "200"

  response_models = {
    "application/json" = "Empty"
  }

  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = false
    "method.response.header.Access-Control-Allow-Methods" = false
    "method.response.header.Access-Control-Allow-Origin" = false
  }
}

resource "aws_api_gateway_integration_response" "turbot_accounts_integration_response_options" {
  depends_on  = [
    aws_api_gateway_integration.turbot_accounts_integration_request_options,
    aws_api_gateway_method_response.turbot_accounts_method_response_options_200
  ]
  rest_api_id = aws_api_gateway_rest_api.api_gateway.id
  resource_id = aws_api_gateway_resource.turbot_accounts_path.id
  http_method = aws_api_gateway_method.turbot_accounts_method_request_options.http_method
  status_code = "200"

  response_templates  = {
    "application/json" = ""
  }

  response_parameters  = {
    "method.response.header.Access-Control-Allow-Methods" = "'DELETE,GET,HEAD,OPTIONS,PATCH,POST,PUT'"
    "method.response.header.Access-Control-Allow-Headers" = "'Content-Type,Authorization,X-Amz-Date,X-Api-Key,X-Amz-Security-Token'"
    "method.response.header.Access-Control-Allow-Origin"  = "'*'"
  }
}

### /turbot/joinlab path ####
resource "aws_api_gateway_resource" "turbot_joinlab_path" {
  rest_api_id = aws_api_gateway_rest_api.api_gateway.id
  parent_id   = aws_api_gateway_resource.turbot_path.id
  path_part   = "joinlab"
}

### /turbot/joinlab post ####
resource "aws_api_gateway_method" "turbot_joinlab_method_request_post" {
  rest_api_id   = aws_api_gateway_rest_api.api_gateway.id
  resource_id   = aws_api_gateway_resource.turbot_joinlab_path.id
  http_method   = "POST"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "turbot_joinlab_integration_request_post" {
  rest_api_id             = aws_api_gateway_rest_api.api_gateway.id
  resource_id             = aws_api_gateway_resource.turbot_joinlab_path.id
  http_method             = aws_api_gateway_method.turbot_joinlab_method_request_post.http_method
  type                    = "AWS"
  content_handling        = "CONVERT_TO_TEXT"
  integration_http_method = "POST"
  uri                     = "arn:aws:apigateway:${var.region}:lambda:path/2015-03-31/functions/${data.aws_lambda_function.gcl_turbot_joinlab.arn}/invocations"
  passthrough_behavior    = "WHEN_NO_TEMPLATES"

  request_templates = {
    "application/json" = <<EOF
{"body":"$util.escapeJavaScript($input.json('$')).replaceAll("\\'","'")"}
EOF
  }
}

resource "aws_api_gateway_method_response" "turbot_joinlab_method_response_200" {
  depends_on  = [aws_api_gateway_integration.turbot_joinlab_integration_request_post]
  rest_api_id = aws_api_gateway_rest_api.api_gateway.id
  resource_id = aws_api_gateway_resource.turbot_joinlab_path.id
  http_method = aws_api_gateway_method.turbot_joinlab_method_request_post.http_method
  status_code = "200"

  response_models = {
    "application/json" = "Empty"
  }
}

resource "aws_api_gateway_integration_response" "turbot_joinlab_integration_response" {
  depends_on  = [
    aws_api_gateway_integration.turbot_joinlab_integration_request_post,
    aws_api_gateway_method_response.turbot_joinlab_method_response_200
  ]
  rest_api_id = aws_api_gateway_rest_api.api_gateway.id
  resource_id = aws_api_gateway_resource.turbot_joinlab_path.id
  http_method = aws_api_gateway_method.turbot_joinlab_method_request_post.http_method
  status_code = "200"
}

### /turbot/joinlab options ####
resource "aws_api_gateway_method" "turbot_joinlab_method_request_options" {
  depends_on    = [aws_api_gateway_resource.turbot_joinlab_path]
  rest_api_id   = aws_api_gateway_rest_api.api_gateway.id
  resource_id   = aws_api_gateway_resource.turbot_joinlab_path.id
  http_method   = "OPTIONS"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "turbot_joinlab_integration_request_options" {
  depends_on           = [aws_api_gateway_method.turbot_joinlab_method_request_options]
  rest_api_id          = aws_api_gateway_rest_api.api_gateway.id
  resource_id          = aws_api_gateway_resource.turbot_joinlab_path.id
  http_method          = aws_api_gateway_method.turbot_joinlab_method_request_options.http_method
  type                 = "MOCK"
  passthrough_behavior = "WHEN_NO_MATCH"
  request_templates    = {
     "application/json" = jsonencode({
       statusCode = 200
       }
     )
  }
}

resource "aws_api_gateway_method_response" "turbot_joinlab_method_response_options_200" {
  depends_on  = [aws_api_gateway_integration.turbot_joinlab_integration_request_options]
  rest_api_id = aws_api_gateway_rest_api.api_gateway.id
  resource_id = aws_api_gateway_resource.turbot_joinlab_path.id
  http_method = aws_api_gateway_method.turbot_joinlab_method_request_options.http_method
  status_code = "200"

  response_models = {
    "application/json" = "Empty"
  }

  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = false
    "method.response.header.Access-Control-Allow-Methods" = false
    "method.response.header.Access-Control-Allow-Origin" = false
  }
}

resource "aws_api_gateway_integration_response" "turbot_joinlab_integration_response_options" {
  depends_on  = [
    aws_api_gateway_integration.turbot_joinlab_integration_request_options,
    aws_api_gateway_method_response.turbot_joinlab_method_response_options_200
  ]
  rest_api_id = aws_api_gateway_rest_api.api_gateway.id
  resource_id = aws_api_gateway_resource.turbot_joinlab_path.id
  http_method = aws_api_gateway_method.turbot_joinlab_method_request_options.http_method
  status_code = "200"

  response_parameters  = {
    "method.response.header.Access-Control-Allow-Methods" = "'DELETE,GET,HEAD,OPTIONS,PATCH,POST,PUT'"
    "method.response.header.Access-Control-Allow-Headers" = "'Content-Type,Authorization,X-Amz-Date,X-Api-Key,X-Amz-Security-Token'"
    "method.response.header.Access-Control-Allow-Origin" = "'*'"
  }
}

### /proxy path ####
resource "aws_api_gateway_resource" "proxy_path" {
  rest_api_id = aws_api_gateway_rest_api.api_gateway.id
  parent_id   = aws_api_gateway_rest_api.api_gateway.root_resource_id
  path_part   = "{proxy+}"
}

resource "aws_api_gateway_method" "proxy_any" {
  rest_api_id   = aws_api_gateway_rest_api.api_gateway.id
  resource_id   = aws_api_gateway_resource.proxy_path.id
  http_method   = "ANY"
  authorization = "NONE"

  request_parameters = {
    "method.request.header.Content-Disposition" = false
    "method.request.header.Content-Type"        = false
    "method.request.path.proxy" = true
  }
}

resource "aws_api_gateway_integration" "proxy_s3_integration" {
  rest_api_id             = aws_api_gateway_rest_api.api_gateway.id
  resource_id             = aws_api_gateway_resource.proxy_path.id
  http_method             = aws_api_gateway_method.proxy_any.http_method
  type                    = "AWS"
  credentials             = aws_iam_role.api_gateway_role.arn
  integration_http_method = "ANY"
  uri                     = "arn:aws:apigateway:us-east-1:s3:path/${var.s3_bucket_name}/{proxy}"
  passthrough_behavior    = "WHEN_NO_MATCH"
  cache_key_parameters    = ["method.request.path.proxy"]

  request_parameters  = {
    "integration.request.header.Content-Disposition" = "method.request.header.Content-Disposition"
    "integration.request.header.Content-Type"        = "method.request.header.Content-Type"
    "integration.request.path.proxy"                 = "method.request.path.proxy"
  }
}

resource "aws_api_gateway_method_response" "proxy_response_200" {
  depends_on  = [aws_api_gateway_integration.proxy_s3_integration]
  rest_api_id = aws_api_gateway_rest_api.api_gateway.id
  resource_id = aws_api_gateway_resource.proxy_path.id
  http_method = aws_api_gateway_method.proxy_any.http_method
  status_code = "200"

  response_parameters = {
    "method.response.header.Content-Disposition" = false
    "method.response.header.Content-Type"        = false
  }
}

resource "aws_api_gateway_integration_response" "proxy_s3_integration_response" {
  depends_on  = [
    aws_api_gateway_integration.proxy_s3_integration,
    aws_api_gateway_method_response.proxy_response_200
  ]
  rest_api_id = aws_api_gateway_rest_api.api_gateway.id
  resource_id = aws_api_gateway_resource.proxy_path.id
  http_method = aws_api_gateway_method.proxy_any.http_method
  status_code = "200"

  response_parameters  = {
    "method.response.header.Content-Disposition" = "integration.response.header.Content-Disposition"
    "method.response.header.Content-Type"        = "integration.response.header.Content-Type"
  }

  # response_templates = {}
}

resource "aws_api_gateway_method" "proxy_options" {
  depends_on    = [aws_api_gateway_resource.proxy_path]
  rest_api_id   = aws_api_gateway_rest_api.api_gateway.id
  resource_id   = aws_api_gateway_resource.proxy_path.id
  http_method   = "OPTIONS"
  authorization = "NONE"

  request_parameters = {
    "method.request.path.proxy" = true
  }
}

resource "aws_api_gateway_integration" "proxy_mock_integration" {
  depends_on              = [aws_api_gateway_method.proxy_options]
  rest_api_id             = aws_api_gateway_rest_api.api_gateway.id
  resource_id             = aws_api_gateway_resource.proxy_path.id
  http_method             = aws_api_gateway_method.proxy_options.http_method
  type                    = "MOCK"
  passthrough_behavior    = "WHEN_NO_MATCH"

  request_templates = {
     "application/json" = jsonencode({
       statusCode = 200
       }
     )
  }
}

resource "aws_api_gateway_method_response" "proxy_mock_response_200" {
  depends_on  = [aws_api_gateway_integration.proxy_mock_integration]
  rest_api_id = aws_api_gateway_rest_api.api_gateway.id
  resource_id = aws_api_gateway_resource.proxy_path.id
  http_method = aws_api_gateway_method.proxy_options.http_method
  status_code = "200"

  response_models = {
    "application/json" = "Empty"
  }

  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = false
    "method.response.header.Access-Control-Allow-Methods" = false
    "method.response.header.Access-Control-Allow-Origin" = false
  }
}

resource "aws_api_gateway_integration_response" "proxy_mock_integration_response" {
  depends_on  = [
    aws_api_gateway_integration.proxy_mock_integration,
    aws_api_gateway_method_response.proxy_mock_response_200
  ]
  rest_api_id = aws_api_gateway_rest_api.api_gateway.id
  resource_id = aws_api_gateway_resource.proxy_path.id
  http_method = aws_api_gateway_method.proxy_options.http_method
  status_code = "200"

  response_parameters  = {
    "method.response.header.Access-Control-Allow-Methods" = "'DELETE,GET,HEAD,OPTIONS,PATCH,POST,PUT'"
    "method.response.header.Access-Control-Allow-Headers" = "'Content-Type,Authorization,X-Amz-Date,X-Api-Key,X-Amz-Security-Token'"
    "method.response.header.Access-Control-Allow-Origin" = "'*'"
  }
}

resource "aws_api_gateway_deployment" "this" {
  depends_on = [
    aws_api_gateway_integration_response.root_s3_integration_response,
    aws_api_gateway_integration_response.v1_mock_integration_response,
    aws_api_gateway_integration_response.jira_issue_integration_response_post,
    aws_api_gateway_integration_response.jira_issue_integration_response_options,
    aws_api_gateway_integration_response.jira_transitions_integration_response,
    aws_api_gateway_integration_response.jira_transitions_integration_response_options,
    aws_api_gateway_integration_response.turbot_accounts_integration_response_get,
    aws_api_gateway_integration_response.turbot_accounts_integration_response_options,
    aws_api_gateway_integration_response.turbot_joinlab_integration_response,
    aws_api_gateway_integration_response.turbot_joinlab_integration_response_options,
    aws_api_gateway_integration_response.proxy_s3_integration_response,
    aws_api_gateway_integration_response.proxy_mock_integration_response
  ]
  rest_api_id = aws_api_gateway_rest_api.api_gateway.id

  triggers = {
    redeployment = sha1(jsonencode(aws_api_gateway_rest_api.api_gateway.body))
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_api_gateway_stage" "stage_to_deploy" {
  deployment_id = aws_api_gateway_deployment.this.id
  rest_api_id   = aws_api_gateway_rest_api.api_gateway.id
  stage_name    = var.api_gateway_stage_name
}

resource "aws_api_gateway_domain_name" "custom_domain_name" {
  domain_name              = var.custom_domain_name
  regional_certificate_arn = var.custom_domain_name_certificate

  endpoint_configuration {
    types = ["REGIONAL"]
  }
}

resource "aws_api_gateway_base_path_mapping" "custom_domain_name_mapping" {
  api_id      = aws_api_gateway_rest_api.api_gateway.id
  stage_name  = aws_api_gateway_stage.stage_to_deploy.stage_name
  domain_name = aws_api_gateway_domain_name.custom_domain_name.domain_name
}

resource "aws_lambda_permission" "allow_api_gateway_to_call_lambda_gcl_jira_issue" {
  depends_on    = [aws_api_gateway_rest_api.api_gateway]
  function_name = data.aws_lambda_function.gcl_jira_issue.function_name
  statement_id  = "AllowApiGatewayToCallLambdaGCLJiraIssue"
  action        = "lambda:InvokeFunction"
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.api_gateway.execution_arn}/*/*"
}

resource "aws_lambda_permission" "allow_api_gateway_to_call_lambda_gcl_jira_transitions" {
  depends_on    = [aws_api_gateway_rest_api.api_gateway]
  function_name = data.aws_lambda_function.gcl_jira_transitions.function_name
  statement_id  = "AllowApiGatewayToCallLambdaGCLJiraTransitions"
  action        = "lambda:InvokeFunction"
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.api_gateway.execution_arn}/*/*"
}

resource "aws_lambda_permission" "allow_api_gateway_to_call_lambda_gcl_turbot_accounts" {
  depends_on    = [aws_api_gateway_rest_api.api_gateway]
  function_name = data.aws_lambda_function.gcl_turbot_accounts.function_name
  statement_id  = "AllowApiGatewayToCallLambdaGCLTurbotAccounts"
  action        = "lambda:InvokeFunction"
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.api_gateway.execution_arn}/*/*"
}

resource "aws_lambda_permission" "allow_api_gateway_to_call_lambda_gcl_turbot_joinlab" {
  depends_on    = [aws_api_gateway_rest_api.api_gateway]
  function_name = data.aws_lambda_function.gcl_turbot_joinlab.arn
  statement_id  = "AllowApiGatewayToCallLambdaGCLTurbotAccounts"
  action        = "lambda:InvokeFunction"
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.api_gateway.execution_arn}/*/*"
}

resource "aws_api_gateway_method_settings" "api_gateway_monitoring" {
  depends_on  = [aws_api_gateway_stage.stage_to_deploy]
  rest_api_id = aws_api_gateway_rest_api.api_gateway.id
  stage_name  = aws_api_gateway_stage.stage_to_deploy.stage_name
  method_path = "*/*"

  settings {
    metrics_enabled = true
    logging_level   = "INFO"
  }
}