# ==============================================================================
# S3 - Media Bucket (files & images)
# ==============================================================================
# Private bucket — CloudFront is the only public entry point.
# ECS tasks access S3 directly via the free S3 Gateway Endpoint (no NAT cost).
#
# Lifecycle: objects transition to Standard-IA after 30 days.
# Standard-IA is ~60% cheaper than Standard for infrequently read files/images.
# ==============================================================================

resource "aws_s3_bucket" "media" {
  bucket        = "${var.project_name}-media"
  force_destroy = var.s3_force_destroy

  tags = {
    Name = "${var.project_name}-media"
  }
}

# Block all public access — CloudFront OAC is the only way in from the internet
resource "aws_s3_bucket_public_access_block" "media" {
  bucket                  = aws_s3_bucket.media.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "media" {
  bucket = aws_s3_bucket.media.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "media" {
  bucket = aws_s3_bucket.media.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# ------------------------------------------------------------------------------
# Lifecycle: Standard → Standard-IA after 30 days
# Standard-IA requires objects >= 128 KB and >= 30 days old.
# Noncurrent versions expire after 90 days to control storage costs.
# ------------------------------------------------------------------------------
resource "aws_s3_bucket_lifecycle_configuration" "media" {
  bucket = aws_s3_bucket.media.id

  rule {
    id     = "transition-to-ia"
    status = "Enabled"

    filter {
      prefix = ""
    }

    transition {
      days          = 30
      storage_class = "STANDARD_IA"
    }

    noncurrent_version_transition {
      noncurrent_days = 30
      storage_class   = "STANDARD_IA"
    }

    noncurrent_version_expiration {
      noncurrent_days = 90
    }
  }
}

# CORS — allows the browser to upload directly and fetch media from the CDN domain
resource "aws_s3_bucket_cors_configuration" "media" {
  bucket = aws_s3_bucket.media.id

  cors_rule {
    allowed_headers = ["*"]
    allowed_methods = ["GET", "PUT", "POST", "DELETE", "HEAD"]
    allowed_origins = [
      "https://${var.domain_name}",
      "https://www.${var.domain_name}",
      "https://cdn.${var.domain_name}",
    ]
    expose_headers  = ["ETag"]
    max_age_seconds = 3000
  }
}

# ==============================================================================
# S3 Gateway Endpoint
# ==============================================================================
# Free VPC endpoint — routes S3 traffic over the AWS backbone instead of
# through NAT Gateways, eliminating data-transfer charges for ECS→S3 traffic.
# Attached to both private and public route tables so all subnets benefit.
# ==============================================================================
resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.main.id
  service_name      = "com.amazonaws.${var.aws_region}.s3"
  vpc_endpoint_type = "Gateway"

  route_table_ids = concat(
    aws_route_table.private[*].id,
    [aws_route_table.public.id]
  )

  tags = {
    Name = "${var.project_name}-s3-endpoint"
  }
}

# ==============================================================================
# Bucket Policy
# ==============================================================================
# Two principals are allowed:
#   1. CloudFront OAC  — GetObject only (public reads via CDN)
#   2. VPC Endpoint    — full CRUD so ECS tasks can upload/delete files
# ==============================================================================
resource "aws_s3_bucket_policy" "media" {
  bucket     = aws_s3_bucket.media.id
  depends_on = [aws_s3_bucket_public_access_block.media]

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowCloudFrontOAC"
        Effect = "Allow"
        Principal = {
          Service = "cloudfront.amazonaws.com"
        }
        Action   = "s3:GetObject"
        Resource = "${aws_s3_bucket.media.arn}/*"
        Condition = {
          StringEquals = {
            "AWS:SourceArn" = aws_cloudfront_distribution.media.arn
          }
        }
      },
      {
        Sid       = "AllowVPCEndpoint"
        Effect    = "Allow"
        Principal = "*"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket",
        ]
        Resource = [
          aws_s3_bucket.media.arn,
          "${aws_s3_bucket.media.arn}/*",
        ]
        Condition = {
          StringEquals = {
            "aws:sourceVpce" = aws_vpc_endpoint.s3.id
          }
        }
      },
    ]
  })
}
