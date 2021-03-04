resource "random_id" "sts" {
  keepers = {
    version = var.sts_policy_version
    mode    = local.sts_policy_mode
    mx      = join("; ", local.mx_servers)
    max_age = var.sts_policy_maxage
  }
  byte_length = 8
}

resource "aws_s3_bucket" "sts" {
  bucket = local.sts_fqdn

  versioning {
    enabled = true
  }

  server_side_encryption_configuration {
    rule {
      apply_server_side_encryption_by_default {
        sse_algorithm = "AES256"
      }
    }
  }

  tags = merge(
    var.additional_tags,
    {
      ManagedBy = "Terraform"
      Changed   = formatdate("YYYY-MM-DD hh:mm ZZZ", timestamp())
    },
  )
}

resource "aws_s3_bucket_public_access_block" "sts" {
  bucket                  = aws_s3_bucket.sts.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_object" "sts" {
  bucket                 = aws_s3_bucket.sts.id
  key                    = ".well-known/mta-sts.txt"
  server_side_encryption = "AES256"
  content_type           = "text/plain"
  content                = "${local.sts_policy_content}\r\n"

  tags = merge(
    var.additional_tags,
    {
      ManagedBy = "Terraform"
      Version   = random_id.sts.dec
      Changed   = formatdate("YYYY-MM-DD hh:mm ZZZ", timestamp())
    },
  )
}

resource "aws_s3_bucket_object" "favicon" {
  bucket                 = aws_s3_bucket.sts.id
  key                    = "favicon.ico"
  server_side_encryption = "AES256"
  content_type           = "image/x-icon"
  source                 = "${path.module}/favicon.ico"

  tags = merge(
    var.additional_tags,
    {
      ManagedBy = "Terraform"
      Changed   = formatdate("YYYY-MM-DD hh:mm ZZZ", timestamp())
    },
  )
}

resource "aws_route53_record" "smtp_tls" {
  allow_overwrite = true
  zone_id         = var.zone_id
  name            = "_smtp._tls"
  type            = "TXT"
  ttl             = var.record_ttl
  records         = [local.tls_policy]

  lifecycle {
    create_before_destroy = false
  }
}

resource "aws_route53_record" "sts" {
  allow_overwrite = true
  zone_id         = var.zone_id
  name            = "_mta-sts"
  type            = "TXT"
  ttl             = var.record_ttl
  records         = [local.sts_policy]

  lifecycle {
    create_before_destroy = false
  }
}

resource "aws_route53_record" "mx" {
  count = length(local.mx_records) >= 1 ? 1 : 0

  allow_overwrite = true
  zone_id         = var.zone_id
  name            = local.zone_name
  type            = "MX"
  ttl             = var.record_ttl
  records         = local.mx_records

  lifecycle {
    create_before_destroy = false
  }
}
