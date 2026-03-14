# ==============================================================================
# WAF — AWS WAFv2 Web ACL (Regional, attached to ALB)
# ==============================================================================
# Provides Layer 7 protection using AWS Managed Rule Groups covering:
#   - OWASP Top 10 (SQLi, XSS, LFI, RFI, command injection)
#   - Known bad inputs (Log4j, SSRF shellcode patterns)
#   - IP reputation (botnets, scrapers, scanners)
#   - Rate limiting per IP (brute force / DoS mitigation)
#
# Scope is REGIONAL — attached to the ALB.
# CloudFront WAF (scope = CLOUDFRONT) would require us-east-1 and is separate.
#
# Cost: ~$5/month base + $1/month per rule group + $0.60/million requests.
# Set enable_waf = false in dev to avoid the standing charge.
# ==============================================================================

resource "aws_wafv2_web_acl" "main" {
  count = var.enable_waf ? 1 : 0

  name        = "${var.project_name}-waf"
  description = "WAF for ${var.project_name} ALB - OWASP, reputation, rate limiting"
  scope       = "REGIONAL"

  default_action {
    allow {}
  }

  # ── Rule 1: IP Reputation List ─────────────────────────────────────────────
  # Blocks IPs associated with botnets, scrapers, and anonymous proxies.
  # IoT devices (M5Stack) send directly to Kinesis — a native AWS endpoint that
  # bypasses the ALB and WAF entirely. This rule only affects browser traffic.
  rule {
    name     = "AWSManagedRulesAmazonIpReputationList"
    priority = 10

    override_action {
      none {} # Block — does not affect IoT devices (they bypass ALB/WAF)
    }

    statement {
      managed_rule_group_statement {
        vendor_name = "AWS"
        name        = "AWSManagedRulesAmazonIpReputationList"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${var.project_name}-ip-reputation"
      sampled_requests_enabled   = true
    }
  }

  # ── Rule 2: Large Body Monitor (> 15 MB) ──────────────────────────────────
  # Counts (does not block) requests with a body larger than 15MB.
  # AWS's built-in SizeRestrictions_BODY fires at 8KB which is too aggressive
  # for modern file uploads (profile photos, resumes). This rule flags genuinely
  # oversized uploads in CloudWatch for monitoring — Laravel validation handles
  # the actual rejection with a proper error response to the user.
  rule {
    name     = "MonitorOversizedBody"
    priority = 15

    action {
      count {}
    }

    statement {
      size_constraint_statement {
        comparison_operator = "GT"
        size                = 15728640 # 15 MB in bytes
        field_to_match {
          body {
            oversize_handling = "CONTINUE"
          }
        }
        text_transformation {
          priority = 0
          type     = "NONE"
        }
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${var.project_name}-large-body-monitor"
      sampled_requests_enabled   = true
    }
  }

  # ── Rule 4: Per-IP Rate Limit ──────────────────────────────────────────────
  # Blocks a single IP that sends more than 2000 requests in any 5-minute window.
  # Protects against brute-force login, credential stuffing, and basic DoS.
  rule {
    name     = "RateLimitPerIP"
    priority = 20

    action {
      block {}
    }

    statement {
      rate_based_statement {
        limit              = 2000  # requests per 5-minute window per IP
        aggregate_key_type = "IP"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${var.project_name}-rate-limit"
      sampled_requests_enabled   = true
    }
  }

  # ── Rule 3: Core Rule Set (OWASP Top 10) ──────────────────────────────────
  # Covers SQL injection, XSS, LFI, RFI, HTTP protocol violations, and more.
  #
  # Overrides (COUNT instead of BLOCK):
  #   - SizeRestrictions_BODY: fires on request body > 8KB — triggered by file
  #     uploads (profile photo + resume) in the employee create/update forms.
  #   - NoUserAgent_HEADER: blocks requests with no User-Agent — Inertia.js
  #     prefetch requests sometimes omit this header.
  rule {
    name     = "AWSManagedRulesCommonRuleSet"
    priority = 30

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        vendor_name = "AWS"
        name        = "AWSManagedRulesCommonRuleSet"

        # Body > 8KB — triggered by file uploads (photos, resumes)
        rule_action_override {
          name = "SizeRestrictions_BODY"
          action_to_use {
            count {}
          }
        }

        # XSS scanner misreads multipart form bodies containing file data
        # as XSS patterns — false positive on binary file uploads
        rule_action_override {
          name = "CrossSiteScripting_BODY"
          action_to_use {
            count {}
          }
        }

        # Inertia.js prefetch requests sometimes omit User-Agent
        rule_action_override {
          name = "NoUserAgent_HEADER"
          action_to_use {
            count {}
          }
        }
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${var.project_name}-common-rules"
      sampled_requests_enabled   = true
    }
  }

  # ── Rule 4: Known Bad Inputs ───────────────────────────────────────────────
  # Blocks patterns associated with Log4Shell (CVE-2021-44228), SSRF,
  # JavaDeserialisation, and shellcode injection.
  rule {
    name     = "AWSManagedRulesKnownBadInputsRuleSet"
    priority = 40

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        vendor_name = "AWS"
        name        = "AWSManagedRulesKnownBadInputsRuleSet"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${var.project_name}-bad-inputs"
      sampled_requests_enabled   = true
    }
  }

  # ── Rule 5: SQL Injection Rule Set ────────────────────────────────────────
  # Additional SQLi detection beyond what the Common Rule Set covers —
  # catches advanced evasion patterns (encoding, whitespace bypass, etc.).
  rule {
    name     = "AWSManagedRulesSQLiRuleSet"
    priority = 50

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        vendor_name = "AWS"
        name        = "AWSManagedRulesSQLiRuleSet"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${var.project_name}-sqli"
      sampled_requests_enabled   = true
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "${var.project_name}-waf"
    sampled_requests_enabled   = true
  }

  tags = {
    Name        = "${var.project_name}-waf"
    Environment = var.environment
  }
}

# ==============================================================================
# Associate WAF Web ACL with the ALB
# ==============================================================================

resource "aws_wafv2_web_acl_association" "alb" {
  count = var.enable_waf ? 1 : 0

  resource_arn = aws_lb.main.arn
  web_acl_arn  = aws_wafv2_web_acl.main[0].arn
}

# ==============================================================================
# WAF Logging — CloudWatch Log Group
# ==============================================================================
# WAF log group name MUST start with "aws-waf-logs-" — AWS enforces this.

resource "aws_cloudwatch_log_group" "waf" {
  count = var.enable_waf ? 1 : 0

  name              = "aws-waf-logs-${var.project_name}"
  retention_in_days = 30

  tags = {
    Name        = "aws-waf-logs-${var.project_name}"
    Environment = var.environment
  }
}

resource "aws_wafv2_web_acl_logging_configuration" "main" {
  count = var.enable_waf ? 1 : 0

  log_destination_configs = [aws_cloudwatch_log_group.waf[0].arn]
  resource_arn            = aws_wafv2_web_acl.main[0].arn

  # Redact Authorization header from logs — never log bearer tokens / API keys
  redacted_fields {
    single_header {
      name = "authorization"
    }
  }
}
