terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.0"
    }
  }

  backend "s3" {
    bucket = "jett-tfstate-2026"
    key    = "cloud-resume-challenge/terraform.tfstate"
    region = "us-east-1"
  }
}

provider "aws" {
  region  = "us-east-1"
}

resource "aws_iam_openid_connect_provider" "github" {
  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1"]
}

resource "aws_iam_role" "github_actions_deploy" {
  name = "github-actions-resume-deploy"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Federated = aws_iam_openid_connect_provider.github.arn
      }
      Action = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
        }
        StringLike = {
            "token.actions.githubusercontent.com:sub" = [
                "repo:jettbtirrell/cloud-resume-challenge:ref:refs/heads/main",
                "repo:jettbtirrell@*/cloud-resume-challenge@*:ref:refs/heads/main"
            ]
        }
      }
    }]
  })
}

resource "aws_iam_role_policy" "deploy_permissions" {
  name = "resume-deploy-permissions"
  role = aws_iam_role.github_actions_deploy.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "S3Sync"
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:GetObject",
          "s3:ListBucket",
          "s3:DeleteObject"
        ]
        Resource = [
          "arn:aws:s3:::jett-cloud-resume-2026",
          "arn:aws:s3:::jett-cloud-resume-2026/*"
        ]
      },
      {
        Sid    = "CloudFrontInvalidate"
        Effect = "Allow"
        Action = [
          "cloudfront:CreateInvalidation"
        ]
        Resource = "arn:aws:cloudfront::945219712931:distribution/EH2FPOYLSG1J4"
      }
    ]
  })
}

resource "aws_dynamodb_table" "visitor_count" {
  name         = "visitor-count"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "id"

  attribute {
    name = "id"
    type = "S"
  }
}

data "archive_file" "lambda_zip" {
  type        = "zip"
  source_file = "${path.module}/../backend/lambda_function.py"
  output_path = "${path.module}/lambda_function.zip"
}

resource "aws_lambda_function" "visitor_count" {
  function_name    = "visitor-count-handler"
  filename         = data.archive_file.lambda_zip.output_path
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256
  handler          = "lambda_function.lambda_handler"
  runtime          = "python3.14"
  role             = aws_iam_role.lambda_exec.arn
}

output "github_actions_role_arn" {
  value = aws_iam_role.github_actions_deploy.arn
}

resource "aws_iam_role" "lambda_exec" {
  name = "visitor-count-handler-role-shfzwrmo"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "lambda.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })

  path = "/service-role/"
}

resource "aws_iam_policy" "lambda_basic_execution" {
  name = "AWSLambdaBasicExecutionRole-01228993-612a-4a5d-a222-7944ef699ee4"
  path = "/service-role/"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = "logs:CreateLogGroup"
        Resource = "arn:aws:logs:us-east-1:945219712931:*"
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = [
          "arn:aws:logs:us-east-1:945219712931:log-group:/aws/lambda/visitor-count-handler:*"
        ]
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = aws_iam_policy.lambda_basic_execution.arn
}

resource "aws_iam_role_policy" "lambda_dynamodb_access" {
  name = "visitor-count-dynamodb-access"
  role = aws_iam_role.lambda_exec.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid    = "AllowVisitorCounterAccess"
      Effect = "Allow"
      Action = [
        "dynamodb:UpdateItem",
        "dynamodb:GetItem"
      ]
      Resource = "arn:aws:dynamodb:us-east-1:945219712931:table/visitor-count"
    }]
  })
}

resource "aws_apigatewayv2_api" "visitor_count" {
  name          = "visitor-count-api"
  protocol_type = "HTTP"

  cors_configuration {
    allow_origins = ["*"]
    allow_methods = ["GET"]
  }
}

resource "aws_apigatewayv2_integration" "lambda" {
  api_id                 = aws_apigatewayv2_api.visitor_count.id
  integration_type       = "AWS_PROXY"
  integration_method     = "POST"
  integration_uri        = aws_lambda_function.visitor_count.invoke_arn
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "read_count" {
  api_id    = aws_apigatewayv2_api.visitor_count.id
  route_key = "GET /read_count"
  target    = "integrations/${aws_apigatewayv2_integration.lambda.id}"
}

resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.visitor_count.id
  name        = "$default"
  auto_deploy = true
}

resource "aws_lambda_permission" "api_gateway" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.visitor_count.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.visitor_count.execution_arn}/*/*/read_count"
}

resource "aws_s3_bucket" "resume_site" {
  bucket = "jett-cloud-resume-2026"
}

resource "aws_s3_bucket_public_access_block" "resume_site" {
  bucket = aws_s3_bucket.resume_site.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_policy" "resume_site" {
  bucket = aws_s3_bucket.resume_site.id

  policy = jsonencode({
    Version = "2008-10-17"
    Id      = "PolicyForCloudFrontPrivateContent"
    Statement = [{
      Sid       = "AllowCloudFrontServicePrincipal"
      Effect    = "Allow"
      Principal = { Service = "cloudfront.amazonaws.com" }
      Action    = "s3:GetObject"
      Resource  = "arn:aws:s3:::jett-cloud-resume-2026/*"
      Condition = {
        ArnLike = {
          "AWS:SourceArn" = "arn:aws:cloudfront::945219712931:distribution/EH2FPOYLSG1J4"
        }
      }
    }]
  })
}

resource "aws_cloudfront_distribution" "resume_site" {
  enabled             = true
  default_root_object = "index.html"
  aliases             = ["jettbtirrell.com", "www.jettbtirrell.com"]
  price_class         = "PriceClass_All"
  http_version        = "http2"
  is_ipv6_enabled     = true
  web_acl_id          = "arn:aws:wafv2:us-east-1:945219712931:global/webacl/CreatedByCloudFront-aac033b0/fd52ff7e-0356-4dee-8f1f-ad2d0bae6448"

  origin {
    domain_name              = "jett-cloud-resume-2026.s3.us-east-1.amazonaws.com"
    origin_id                = "jett-cloud-resume-2026.s3.us-east-1.amazonaws.com-mrsbmzuuks2"
    origin_access_control_id = "E2O6T5ULHBJAFY"
  }

  default_cache_behavior {
    target_origin_id       = "jett-cloud-resume-2026.s3.us-east-1.amazonaws.com-mrsbmzuuks2"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]
    compress               = true
    cache_policy_id        = "658327ea-f89d-4fab-a63d-7e88639e58f6"
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    acm_certificate_arn      = "arn:aws:acm:us-east-1:945219712931:certificate/7a6ff9f8-b31e-4e63-9fcb-ae912e3c4769"
    ssl_support_method       = "sni-only"
    minimum_protocol_version = "TLSv1.2_2021"
  }

  tags = {
    Name                     = "jett-resume-site"
  }
}

resource "aws_route53_record" "root" {
  zone_id = "Z0234003OOTYC6RO8G4D"
  name    = "jettbtirrell.com"
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.resume_site.domain_name
    zone_id                = aws_cloudfront_distribution.resume_site.hosted_zone_id
    evaluate_target_health = false
  }
}

resource "aws_route53_record" "www" {
  zone_id = "Z0234003OOTYC6RO8G4D"
  name    = "www.jettbtirrell.com"
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.resume_site.domain_name
    zone_id                = aws_cloudfront_distribution.resume_site.hosted_zone_id
    evaluate_target_health = false
  }
}

resource "aws_iam_role" "github_actions_backend_deploy" {
  name = "github-actions-backend-deploy"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Federated = aws_iam_openid_connect_provider.github.arn
      }
      Action = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
        }
        StringLike = {
          "token.actions.githubusercontent.com:sub" = [
            "repo:jettbtirrell/cloud-resume-challenge:ref:refs/heads/main",
            "repo:jettbtirrell@*/cloud-resume-challenge@*:ref:refs/heads/main"
          ]
        }
      }
    }]
  })
}

resource "aws_iam_role_policy" "backend_deploy_permissions" {
  name = "backend-deploy-permissions"
  role = aws_iam_role.github_actions_backend_deploy.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "LambdaDeploy"
        Effect = "Allow"
        Action = [
          "lambda:UpdateFunctionCode",
          "lambda:UpdateFunctionConfiguration",
          "lambda:GetFunction",
          "lambda:GetPolicy",
          "lambda:ListVersionsByFunction",
          "lambda:GetFunctionCodeSigningConfig"
        ]
        Resource = "arn:aws:lambda:us-east-1:945219712931:function:visitor-count-handler"
      },
      {
        Sid    = "DynamoDBManage"
        Effect = "Allow"
        Action = [
          "dynamodb:DescribeTable"
        ]
        Resource = "arn:aws:dynamodb:us-east-1:945219712931:table/visitor-count"
      },
      {
        Sid    = "ApiGatewayManage"
        Effect = "Allow"
        Action = [
          "apigateway:GET",
          "apigateway:PATCH"
        ]
        Resource = "arn:aws:apigateway:us-east-1::/apis/*"
      },
      {
        Sid    = "IAMPassRole"
        Effect = "Allow"
        Action = ["iam:GetRole", "iam:PassRole"]
        Resource = "arn:aws:iam::945219712931:role/service-role/visitor-count-handler-role-shfzwrmo"
      },
      {
        Sid    = "TerraformStateAccess"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:ListBucket"
        ]
        Resource = [
          "arn:aws:s3:::jett-tfstate-2026",
          "arn:aws:s3:::jett-tfstate-2026/*"
        ]
      },
      {
        Sid    = "IAMReadForState"
        Effect = "Allow"
        Action = [
          "iam:GetOpenIDConnectProvider",
          "iam:GetRole",
          "iam:GetRolePolicy",
          "iam:ListRolePolicies",
          "iam:ListAttachedRolePolicies",
          "iam:GetPolicy",
          "iam:GetPolicyVersion",
          "iam:ListPolicyVersions"
        ]
        Resource = "*"
      },
      {
        Sid    = "DynamoDBReadForState"
        Effect = "Allow"
        Action = [
          "dynamodb:DescribeTable",
          "dynamodb:DescribeContinuousBackups",
          "dynamodb:DescribeTimeToLive",
          "dynamodb:ListTagsOfResource"
        ]
        Resource = "arn:aws:dynamodb:us-east-1:945219712931:table/visitor-count"
      },
      {
        Sid    = "S3ReadForState"
        Effect = "Allow"
        Action = [
          "s3:GetBucketPolicy",
          "s3:GetBucketPublicAccessBlock",
          "s3:GetBucketVersioning",
          "s3:GetBucketAcl",
          "s3:GetEncryptionConfiguration",
          "s3:ListBucket",
          "s3:GetBucketLocation",
          "s3:GetBucketCORS",
          "s3:GetBucketWebsite",
          "s3:GetAccelerateConfiguration",
          "s3:GetBucketRequestPayment"
        ]
        Resource = "arn:aws:s3:::jett-cloud-resume-2026"
      },
      {
        Sid    = "CloudFrontReadForState"
        Effect = "Allow"
        Action = [
          "cloudfront:GetDistribution",
          "cloudfront:ListTagsForResource"
        ]
        Resource = "arn:aws:cloudfront::945219712931:distribution/EH2FPOYLSG1J4"
      },
      {
        Sid    = "Route53ReadForState"
        Effect = "Allow"
        Action = [
          "route53:GetHostedZone",
          "route53:ListResourceRecordSets",
          "route53:ChangeResourceRecordSets"
        ]
        Resource = "arn:aws:route53:::hostedzone/Z0234003OOTYC6RO8G4D"
      }
    ]
  })
}
