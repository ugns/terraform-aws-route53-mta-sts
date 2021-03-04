data "aws_route53_zone" "zone" {
  zone_id = var.zone_id
}

data "aws_iam_policy_document" "lambda" {
  policy_id = "lambda-exec-role"

  statement {
    sid = "CloudwatchLogs"

    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents"
    ]
    resources = ["arn:aws:logs:*:*:*"]
  }
}

data "aws_iam_policy_document" "assume_role" {
  statement {
    sid = "AllowLambdaServiceToAssumeRole"

    actions = ["sts:AssumeRole"]

    principals {
      type = "Service"
      identifiers = [
        "edgelambda.amazonaws.com",
        "lambda.amazonaws.com"
      ]
    }
  }
}

variable "additional_tags" {
  description = "Additional resource tags"
  type        = map(string)
  default     = {}
}

variable "zone_id" {
  description = "AWS Route53 Hosted Zone ID"
  type        = string
}

variable "record_ttl" {
  description = "TTL for all DNS records"
  type        = number
  default     = 3600
}

variable "tls_report_version" {
  description = "Version of SMTP TLS Protocol"
  type        = string
  default     = "TLSRPTv1"
}

variable "tls_report_recipient" {
  description = "Recipient of SMTP TLS Reports"
  type        = string
  default     = null
}

variable "sts_policy_version" {
  description = "Version of MTA Strict Transport Security Protocol"
  type        = string
  default     = "STSv1"
}

variable "sts_policy_mode" {
  description = "MTA Strict Transport Security policy mode. Defaults to 'testing'"
  type        = string
  default     = "testing"

  validation {
    condition     = can(regex("^(enforce|testing|none)$", var.sts_policy_mode))
    error_message = "MTA STS mode must be one of enforce, testing or none."
  }
}

variable "sts_policy_maxage" {
  description = "MTA Strict Transport Security maxage, defaults to 604800 (7 days)"
  type        = number
  default     = 604800
}

variable "mx_records" {
  description = "List of MX Records"
  type        = list(string)
  default     = []
}

locals {
  mx_record_regex      = "/^(?P<priority>\\d+)\\s+(?P<mx_host>\\S+)/"
  zone_name            = data.aws_route53_zone.zone.name
  sts_s3_origin_id     = format("origin-bucket-%s", aws_s3_bucket.sts.id)
  sts_fqdn             = format("mta-sts.%s", local.zone_name)
  tls_report_recipient = var.tls_report_recipient != null ? var.tls_report_recipient : format("smtp-tls-reports@%s", local.zone_name)
  tls_policy           = format("v=%s; rua=mailto:%s;", var.tls_report_version, local.tls_report_recipient)
  mx_records           = [for v in var.mx_records : replace(v, local.mx_record_regex, "$priority $mx_host")]
  mx_servers           = [for v in var.mx_records : replace(v, local.mx_record_regex, "$mx_host")]
  sts_policy           = format("v=%s; id=%s;", var.sts_policy_version, random_id.sts.dec)
  sts_policy_mode      = length(var.mx_records) >= 1 ? var.sts_policy_mode : "none"
  sts_policy_content = join("\r\n",
    flatten([
      format("version: %s", var.sts_policy_version),
      format("mode: %s", local.sts_policy_mode),
      [for mx_host in local.mx_servers : format("mx: %s", lower(mx_host))],
      format("max_age: %s", var.sts_policy_maxage),
    ])
  )
}
