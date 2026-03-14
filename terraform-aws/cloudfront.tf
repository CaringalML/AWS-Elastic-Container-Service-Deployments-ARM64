# ==============================================================================
# CloudFront - Content Delivery for S3 Media
# ==============================================================================
# Serves files and images from the S3 media bucket via a global CDN at
# cdn.<domain_name>.
#
# Access model:
#   Browser → CloudFront (cdn.domain.com) → S3 via OAC (private bucket)
#   ECS app → S3 directly via VPC Gateway Endpoint (no CloudFront involved)
#
# OAC (Origin Access Control) is the modern replacement for OAI — it signs
# requests to S3 with SigV4 so the bucket can stay fully private.
#
# ACM certificate for CloudFront MUST be in us-east-1 regardless of where
# the rest of the infrastructure lives. A provider alias handles this.
# ==============================================================================

# ------------------------------------------------------------------------------
# ACM Certificate — us-east-1 (CloudFront requirement)
# Covers cdn.<domain_name>
# ------------------------------------------------------------------------------
resource "aws_acm_certificate" "cdn" {
  provider          = aws.us_east_1
  domain_name       = "cdn.${var.domain_name}"
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }

  tags = {
    Name = "${var.project_name}-cdn-cert"
  }
}

resource "aws_route53_record" "cdn_cert_validation" {
  for_each = {
    for dvo in aws_acm_certificate.cdn.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }

  zone_id = data.aws_route53_zone.selected.zone_id
  name    = each.value.name
  type    = each.value.type
  ttl     = 60
  records = [each.value.record]
}

resource "aws_acm_certificate_validation" "cdn" {
  provider                = aws.us_east_1
  certificate_arn         = aws_acm_certificate.cdn.arn
  validation_record_fqdns = [for r in aws_route53_record.cdn_cert_validation : r.fqdn]
}

# ------------------------------------------------------------------------------
# Origin Access Control
# Signs every CloudFront → S3 request with SigV4 so the bucket stays private.
# ------------------------------------------------------------------------------
resource "aws_cloudfront_origin_access_control" "media" {
  name                              = "${var.project_name}-media-oac"
  description                       = "OAC for ${var.project_name} S3 media bucket"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

# Managed cache policy — optimised for S3 static content (no query strings/cookies)
data "aws_cloudfront_cache_policy" "caching_optimized" {
  name = "Managed-CachingOptimized"
}

# ------------------------------------------------------------------------------
# CloudFront Distribution
# ------------------------------------------------------------------------------
resource "aws_cloudfront_distribution" "media" {
  enabled     = true
  comment     = "${var.project_name} media CDN"
  price_class = "PriceClass_All" # Global — includes ap-southeast-2 edge locations
  aliases     = ["cdn.${var.domain_name}"]

  origin {
    domain_name              = aws_s3_bucket.media.bucket_regional_domain_name
    origin_id                = "s3-${var.project_name}-media"
    origin_access_control_id = aws_cloudfront_origin_access_control.media.id
  }

  # Default behaviour — applies to all paths not matched below
  default_cache_behavior {
    target_origin_id       = "s3-${var.project_name}-media"
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]
    viewer_protocol_policy = "redirect-to-https"
    compress               = true
    cache_policy_id        = data.aws_cloudfront_cache_policy.caching_optimized.id
  }

  # Images — same cache policy but explicit path for clarity and future overrides
  ordered_cache_behavior {
    path_pattern           = "/images/*"
    target_origin_id       = "s3-${var.project_name}-media"
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]
    viewer_protocol_policy = "redirect-to-https"
    compress               = true
    cache_policy_id        = data.aws_cloudfront_cache_policy.caching_optimized.id
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    acm_certificate_arn      = aws_acm_certificate_validation.cdn.certificate_arn
    ssl_support_method       = "sni-only"
    minimum_protocol_version = "TLSv1.2_2021"
  }

  tags = {
    Name = "${var.project_name}-cdn"
  }

  depends_on = [aws_acm_certificate_validation.cdn]
}

# ------------------------------------------------------------------------------
# Route53 — cdn.<domain_name> → CloudFront
# ------------------------------------------------------------------------------
resource "aws_route53_record" "cdn" {
  zone_id = data.aws_route53_zone.selected.zone_id
  name    = "cdn.${var.domain_name}"
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.media.domain_name
    zone_id                = aws_cloudfront_distribution.media.hosted_zone_id
    evaluate_target_health = false
  }
}

# Output the CDN URL for reference
output "cdn_url" {
  description = "CloudFront CDN URL for media files"
  value       = "https://cdn.${var.domain_name}"
}

output "s3_bucket_name" {
  description = "S3 media bucket name"
  value       = aws_s3_bucket.media.bucket
}
