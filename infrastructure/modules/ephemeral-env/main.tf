locals {
  env_prefix = "ephemeral-${var.environment}"
  pr_label   = "pr-${var.pr_number}"
}

# ---------------------------------------------------------------------------
# VPC
# ---------------------------------------------------------------------------
resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name        = "${local.env_prefix}-vpc"
    EphemeralID = var.environment
  }
}

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id

  tags = {
    Name        = "${local.env_prefix}-igw"
    EphemeralID = var.environment
  }
}

resource "aws_subnet" "public" {
  count                   = 2
  vpc_id                  = aws_vpc.this.id
  cidr_block              = var.subnet_cidrs[count.index]
  map_public_ip_on_launch = true
  availability_zone       = data.aws_availability_zones.available.names[count.index]

  tags = {
    Name        = "${local.env_prefix}-public-${count.index}"
    EphemeralID = var.environment
  }
}

data "aws_availability_zones" "available" {
  state = "available"
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.this.id
  }

  tags = {
    Name        = "${local.env_prefix}-rtb"
    EphemeralID = var.environment
  }
}

resource "aws_route_table_association" "public" {
  count          = 2
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# ---------------------------------------------------------------------------
# Security Groups
# ---------------------------------------------------------------------------
resource "aws_security_group" "ecs" {
  name_prefix = "${local.env_prefix}-ecs-sg-"
  vpc_id      = aws_vpc.this.id

  ingress {
    from_port   = var.container_port
    to_port     = var.container_port
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    EphemeralID = var.environment
  }
}

resource "aws_security_group" "rds" {
  name_prefix = "${local.env_prefix}-rds-sg-"
  vpc_id      = aws_vpc.this.id

  ingress {
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.ecs.id]
  }

  tags = {
    EphemeralID = var.environment
  }
}

# ---------------------------------------------------------------------------
# RDS
# ---------------------------------------------------------------------------
resource "aws_db_subnet_group" "this" {
  name       = "${local.env_prefix}-db-subnet"
  subnet_ids = aws_subnet.public[*].id

  tags = {
    EphemeralID = var.environment
  }
}

resource "aws_db_instance" "this" {
  identifier             = "${local.env_prefix}-db"
  engine                 = "postgres"
  engine_version         = "16.3"
  instance_class         = var.rds_instance_class
  allocated_storage      = var.rds_allocated_storage
  db_name                = "ephemeral"
  username               = "ephemeral"
  password               = random_password.db_password.result
  db_subnet_group_name   = aws_db_subnet_group.this.name
  vpc_security_group_ids = [aws_security_group.rds.id]
  skip_final_snapshot    = true
  publicly_accessible    = false

  tags = {
    EphemeralID = var.environment
  }
}

resource "random_password" "db_password" {
  length  = 24
  special = false
}

resource "aws_ssm_parameter" "db_password" {
  name  = "/ephemeral/${var.environment}/DB_PASSWORD"
  type  = "SecureString"
  value = random_password.db_password.result
}

resource "aws_ssm_parameter" "db_url" {
  name  = "/ephemeral/${var.environment}/DATABASE_URL"
  type  = "SecureString"
  value = "postgresql://ephemeral:${random_password.db_password.result}@${aws_db_instance.this.endpoint}/ephemeral"
}

# ---------------------------------------------------------------------------
# ECS
# ---------------------------------------------------------------------------
resource "aws_ecs_cluster" "this" {
  name = "${local.env_prefix}-cluster"

  tags = {
    EphemeralID = var.environment
  }
}

resource "aws_ecs_task_definition" "app" {
  family                   = "${local.env_prefix}-app"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "256"
  memory                   = "512"
  execution_role_arn       = aws_iam_role.ecs_execution.arn
  task_role_arn            = aws_iam_role.ecs_task.arn

  container_definitions = jsonencode([
    {
      name      = "app"
      image     = var.app_image
      essential = true
      portMappings = [
        {
          containerPort = var.container_port
          hostPort      = var.container_port
          protocol      = "tcp"
        }
      ]
      environment = [
        { name = "DB_HOST",     value = aws_db_instance.this.address },
        { name = "DB_PORT",     value = tostring(aws_db_instance.this.port) },
        { name = "DB_NAME",     value = aws_db_instance.this.db_name },
        { name = "DB_USER",     value = aws_db_instance.this.username },
        { name = "ENVIRONMENT", value = var.environment },
        { name = "PR_NUMBER",   value = var.pr_number },
      ]
      secrets = [
        { name = "DB_PASSWORD", valueFrom = aws_ssm_parameter.db_password.arn }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.app.name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "ecs"
        }
      }
    }
  ])

  tags = {
    EphemeralID = var.environment
  }
}

resource "aws_ecs_service" "app" {
  name            = "${local.env_prefix}-service"
  cluster         = aws_ecs_cluster.this.id
  task_definition = aws_ecs_task_definition.app.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = aws_subnet.public[*].id
    security_groups  = [aws_security_group.ecs.id]
    assign_public_ip = true
  }

  tags = {
    EphemeralID = var.environment
  }
}

resource "aws_cloudwatch_log_group" "app" {
  name              = "/ecs/ephemeral/${var.environment}"
  retention_in_days = 7

  tags = {
    EphemeralID = var.environment
  }
}

# ---------------------------------------------------------------------------
# IAM
# ---------------------------------------------------------------------------
data "aws_iam_policy_document" "ecs_execution_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "ecs_execution" {
  statement {
    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents",
    ]
    resources = ["*"]
  }
  statement {
    actions = [
      "ssm:GetParameters",
      "ssm:GetParameter",
    ]
    resources = [aws_ssm_parameter.db_password.arn, aws_ssm_parameter.db_url.arn]
  }
  statement {
    actions = [
      "ecr:GetDownloadUrlForLayer",
      "ecr:BatchGetImage",
      "ecr:BatchCheckLayerAvailability",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_role" "ecs_execution" {
  name               = "${local.env_prefix}-ecs-execution"
  assume_role_policy = data.aws_iam_policy_document.ecs_execution_assume.json
}

resource "aws_iam_role_policy" "ecs_execution" {
  role   = aws_iam_role.ecs_execution.name
  policy = data.aws_iam_policy_document.ecs_execution.json
}

data "aws_iam_policy_document" "ecs_task_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "ecs_task" {
  name               = "${local.env_prefix}-ecs-task"
  assume_role_policy = data.aws_iam_policy_document.ecs_task_assume.json
}

# ---------------------------------------------------------------------------
# Route53 DNS
# ---------------------------------------------------------------------------
resource "aws_route53_record" "app" {
  zone_id = var.dns_zone_id
  name    = "${local.pr_label}.${var.dns_domain}"
  type    = "A"

  alias {
    name                   = aws_lb.this.dns_name
    zone_id                = aws_lb.this.zone_id
    evaluate_target_health = true
  }
}

# ---------------------------------------------------------------------------
# ALB
# ---------------------------------------------------------------------------
resource "aws_lb" "this" {
  name               = "${local.env_prefix}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.ecs.id]
  subnets            = aws_subnet.public[*].id

  tags = {
    EphemeralID = var.environment
  }
}

resource "aws_lb_target_group" "app" {
  name_prefix = "ep-"
  port        = var.container_port
  protocol    = "HTTP"
  vpc_id      = aws_vpc.this.id
  target_type = "ip"

  health_check {
    path                = "/health"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }

  lifecycle {
    create_before_destroy = true
  }

  tags = {
    EphemeralID = var.environment
  }
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.this.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app.arn
  }
}

# ---------------------------------------------------------------------------
# Auto-scaling
# ---------------------------------------------------------------------------
resource "aws_appautoscaling_target" "ecs" {
  max_capacity       = 2
  min_capacity       = 1
  resource_id        = "service/${aws_ecs_cluster.this.name}/${aws_ecs_service.app.name}"
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace  = "ecs"
}

resource "aws_appautoscaling_policy" "cpu" {
  name               = "${local.env_prefix}-cpu-auto-scaling"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.ecs.resource_id
  scalable_dimension = aws_appautoscaling_target.ecs.scalable_dimension
  service_namespace  = aws_appautoscaling_target.ecs.service_namespace

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    }
    target_value = 70.0
  }
}

# ---------------------------------------------------------------------------
# Last-active tracking (for cleanup Lambda)
# ---------------------------------------------------------------------------
resource "aws_cloudwatch_metric_alarm" "inactive" {
  alarm_name          = "${local.env_prefix}-inactive"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 24
  metric_name         = "RequestCount"
  namespace           = "AWS/ApplicationELB"
  period              = 3600
  statistic           = "Sum"
  threshold           = 1
  alarm_description   = "Triggers when no requests hit the env for 24 hours"
  alarm_actions       = []

  dimensions = {
    LoadBalancer = aws_lb.this.arn_suffix
  }

  tags = {
    EphemeralID = var.environment
  }
}

# ---------------------------------------------------------------------------
# Drift detection state (for scheduled Terraform plan)
# ---------------------------------------------------------------------------
resource "aws_s3_object" "drift_state" {
  bucket = "ephemeral-env-drift-state"
  key    = "${var.environment}/last-known-plan.json"
  content = jsonencode({
    workspace   = var.environment
    pr_number   = var.pr_number
    last_check = time_static.drift.id
  })
}

resource "time_static" "drift" {}
