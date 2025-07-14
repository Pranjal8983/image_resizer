provider "aws" {
  region = "us-east-1"
}

resource "aws_s3_bucket" "image_bucket" {
  bucket = "my-image-upload-bucket-123456"
  force_destroy = true
}

resource "aws_sns_topic" "image_notify" {
  name = "image-resize-topic"
}

resource "aws_sns_topic_subscription" "sms" {
  topic_arn = aws_sns_topic.image_notify.arn
  protocol  = "sms"
  endpoint  = "+11234567890"
}

resource "aws_iam_role" "lambda_exec" {
  name = "lambda-s3-exec-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Action = "sts:AssumeRole",
      Effect = "Allow",
      Principal = {
        Service = "lambda.amazonaws.com"
      }
    }]
  })
}

resource "aws_iam_role_policy" "lambda_policy" {
  name = "lambda-s3-sns-policy"
  role = aws_iam_role.lambda_exec.id

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = ["s3:GetObject", "s3:PutObject"],
        Resource = "${aws_s3_bucket.image_bucket.arn}/*"
      },
      {
        Effect = "Allow",
        Action = ["logs:*"],
        Resource = "*"
      },
      {
        Effect = "Allow",
        Action = "sns:Publish",
        Resource = aws_sns_topic.image_notify.arn
      }
    ]
  })
}

resource "aws_lambda_function" "image_resizer" {
  function_name = "image-resizer"
  role          = aws_iam_role.lambda_exec.arn
  handler       = "image-resizing.lambda_handler"
  runtime       = "python3.10"
  timeout       = 30

  filename         = "lambda/image-resizing.zip"
  source_code_hash = filebase64sha256("lambda/image-resizing.zip")

  environment {
    variables = {
      SNS_TOPIC_ARN = aws_sns_topic.image_notify.arn
      DEST_BUCKET   = aws_s3_bucket.image_bucket.bucket
    }
  }
}

resource "aws_s3_bucket_notification" "bucket_notify" {
  bucket = aws_s3_bucket.image_bucket.id

  lambda_function {
    lambda_function_arn = aws_lambda_function.image_resizer.arn
    events              = ["s3:ObjectCreated:*"]
    filter_prefix       = "uploads/"
    filter_suffix       = ".jpg"
  }

  depends_on = [aws_lambda_permission.allow_bucket]
}

resource "aws_lambda_permission" "allow_bucket" {
  statement_id  = "AllowS3Invoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.image_resizer.function_name
  principal     = "s3.amazonaws.com"
  source_arn    = aws_s3_bucket.image_bucket.arn
}