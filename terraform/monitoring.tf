################################################################################
# SNS Topic for Alerts
################################################################################

resource "aws_sns_topic" "alerts" {
  count = var.enable_monitoring ? 1 : 0

  name = "${local.name}-alerts"

  tags = {
    Name = "${local.name}-alerts"
  }
}

resource "aws_sns_topic_subscription" "email" {
  count = var.enable_monitoring && var.alert_email != "" ? 1 : 0

  topic_arn = aws_sns_topic.alerts[0].arn
  protocol  = "email"
  endpoint  = var.alert_email
}

################################################################################
# CloudWatch Alarms
################################################################################

resource "aws_cloudwatch_metric_alarm" "nat_error_port_allocation" {
  count = var.enable_monitoring && var.enable_nat_gateway ? 1 : 0

  alarm_name          = "${local.name}-nat-error-port-allocation"
  alarm_description   = "NAT Gateway ErrorPortAllocation count exceeded threshold"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "ErrorPortAllocation"
  namespace           = "AWS/NATGateway"
  period              = 300
  statistic           = "Sum"
  threshold           = 0
  treat_missing_data  = "notBreaching"

  alarm_actions = var.alert_email != "" ? [aws_sns_topic.alerts[0].arn] : []

  tags = {
    Name = "${local.name}-nat-error-port-allocation"
  }
}

resource "aws_cloudwatch_metric_alarm" "nat_packets_drop" {
  count = var.enable_monitoring && var.enable_nat_gateway ? 1 : 0

  alarm_name          = "${local.name}-nat-packets-drop"
  alarm_description   = "NAT Gateway PacketsDropCount exceeded threshold"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "PacketsDropCount"
  namespace           = "AWS/NATGateway"
  period              = 300
  statistic           = "Sum"
  threshold           = 0
  treat_missing_data  = "notBreaching"

  alarm_actions = var.alert_email != "" ? [aws_sns_topic.alerts[0].arn] : []

  tags = {
    Name = "${local.name}-nat-packets-drop"
  }
}

resource "aws_cloudwatch_metric_alarm" "sqs_dlq_messages" {
  count = var.enable_monitoring ? 1 : 0

  alarm_name          = "${local.name}-sqs-dlq-messages"
  alarm_description   = "Messages visible in Karpenter DLQ indicates processing failures"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "ApproximateNumberOfMessagesVisible"
  namespace           = "AWS/SQS"
  period              = 300
  statistic           = "Sum"
  threshold           = 0
  treat_missing_data  = "notBreaching"

  dimensions = {
    QueueName = module.karpenter.queue_name
  }

  alarm_actions = var.alert_email != "" ? [aws_sns_topic.alerts[0].arn] : []

  tags = {
    Name = "${local.name}-sqs-dlq-messages"
  }
}

resource "aws_cloudwatch_metric_alarm" "sqs_age_of_oldest_message" {
  count = var.enable_monitoring ? 1 : 0

  alarm_name          = "${local.name}-sqs-age-oldest-message"
  alarm_description   = "Oldest message in Karpenter queue exceeds 5 minutes"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "ApproximateAgeOfOldestMessage"
  namespace           = "AWS/SQS"
  period              = 300
  statistic           = "Maximum"
  threshold           = 300
  treat_missing_data  = "notBreaching"

  dimensions = {
    QueueName = module.karpenter.queue_name
  }

  alarm_actions = var.alert_email != "" ? [aws_sns_topic.alerts[0].arn] : []

  tags = {
    Name = "${local.name}-sqs-age-oldest-message"
  }
}

################################################################################
# CloudWatch Dashboard
################################################################################

resource "aws_cloudwatch_dashboard" "main" {
  count = var.enable_monitoring ? 1 : 0

  dashboard_name = "${local.name}-dashboard"

  dashboard_body = jsonencode({
    widgets = [
      {
        type   = "metric"
        x      = 0
        y      = 0
        width  = 12
        height = 6
        properties = {
          title  = "NAT Gateway - Bytes Processed"
          region = var.region
          metrics = [
            ["AWS/NATGateway", "BytesOutToDestination", { stat = "Sum", period = 300 }],
            ["AWS/NATGateway", "BytesInFromSource", { stat = "Sum", period = 300 }],
          ]
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 0
        width  = 12
        height = 6
        properties = {
          title  = "NAT Gateway - Errors"
          region = var.region
          metrics = [
            ["AWS/NATGateway", "ErrorPortAllocation", { stat = "Sum", period = 300 }],
            ["AWS/NATGateway", "PacketsDropCount", { stat = "Sum", period = 300 }],
          ]
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 6
        width  = 12
        height = 6
        properties = {
          title  = "Karpenter SQS - Messages"
          region = var.region
          metrics = [
            ["AWS/SQS", "ApproximateNumberOfMessagesVisible", "QueueName", module.karpenter.queue_name, { stat = "Sum", period = 60 }],
            ["AWS/SQS", "NumberOfMessagesReceived", "QueueName", module.karpenter.queue_name, { stat = "Sum", period = 60 }],
          ]
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 6
        width  = 12
        height = 6
        properties = {
          title  = "Karpenter SQS - DLQ"
          region = var.region
          metrics = [
            ["AWS/SQS", "ApproximateNumberOfMessagesVisible", "QueueName", module.karpenter.queue_name, { stat = "Sum", period = 60 }],
            ["AWS/SQS", "ApproximateAgeOfOldestMessage", "QueueName", module.karpenter.queue_name, { stat = "Maximum", period = 60 }],
          ]
        }
      },
    ]
  })
}
