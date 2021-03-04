module "acm" {
  source  = "UGNS/acm/aws"
  version = ">= 2.5.1"
  providers = {
    aws = aws.use1
  }

  domain_name = local.sts_fqdn
  tags = merge(
    var.additional_tags,
    {
      ManagedBy = "Terraform"
      Changed   = formatdate("YYYY-MM-DD hh:mm ZZZ", timestamp())
    },
  )
}

resource "aws_cloudfront_origin_access_identity" "sts" {
  comment = "access-identity-${aws_s3_bucket.sts.bucket_domain_name}"
}

data "aws_iam_policy_document" "sts" {
  policy_id = "PolicyForCloudFrontPrivateContent"

  statement {
    sid = 1

    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.sts.arn}/*"]

    principals {
      type        = "AWS"
      identifiers = [aws_cloudfront_origin_access_identity.sts.iam_arn]
    }
  }
}

data "aws_cloudfront_cache_policy" "optimized" {
  name = "Managed-CachingOptimized"
}

data "aws_cloudfront_origin_request_policy" "s3origin" {
  name = "Managed-CORS-S3Origin"
}

resource "aws_s3_bucket_policy" "sts" {
  bucket = aws_s3_bucket.sts.id
  policy = data.aws_iam_policy_document.sts.json
}

resource "aws_cloudfront_distribution" "sts" {
  enabled             = true
  is_ipv6_enabled     = true
  wait_for_deployment = true
  comment             = "MTA-STS: ${local.zone_name}"

  origin {
    domain_name = aws_s3_bucket.sts.bucket_regional_domain_name
    origin_id   = local.sts_s3_origin_id

    s3_origin_config {
      origin_access_identity = aws_cloudfront_origin_access_identity.sts.cloudfront_access_identity_path
    }
  }

  aliases = [local.sts_fqdn]

  default_cache_behavior {
    allowed_methods          = ["GET", "HEAD"]
    cached_methods           = ["GET", "HEAD"]
    target_origin_id         = local.sts_s3_origin_id
    compress                 = true
    cache_policy_id          = data.aws_cloudfront_cache_policy.optimized.id
    origin_request_policy_id = data.aws_cloudfront_origin_request_policy.s3origin.id
    viewer_protocol_policy   = "redirect-to-https"

    lambda_function_association {
      event_type = "origin-response"
      lambda_arn = aws_lambda_function.origin_response.qualified_arn
    }
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    minimum_protocol_version = "TLSv1.2_2019"
    acm_certificate_arn      = module.acm.this_acm_certificate_arn
    ssl_support_method       = "sni-only"
  }

  tags = merge(
    var.additional_tags,
    {
      ManagedBy = "Terraform"
      Changed   = formatdate("YYYY-MM-DD hh:mm ZZZ", timestamp())
    },
  )
}

resource "aws_route53_record" "mta-sts_A" {
  allow_overwrite = true
  zone_id         = var.zone_id
  name            = "mta-sts"
  type            = "A"

  alias {
    name                   = aws_cloudfront_distribution.sts.domain_name
    zone_id                = aws_cloudfront_distribution.sts.hosted_zone_id
    evaluate_target_health = false
  }
}

resource "aws_route53_record" "mta-sts_AAAA" {
  allow_overwrite = true
  zone_id         = var.zone_id
  name            = "mta-sts"
  type            = "AAAA"

  alias {
    name                   = aws_cloudfront_distribution.sts.domain_name
    zone_id                = aws_cloudfront_distribution.sts.hosted_zone_id
    evaluate_target_health = false
  }
}