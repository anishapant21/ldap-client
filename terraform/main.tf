# main.tf - Using existing infrastructure resources

# Configure AWS provider
provider "aws" {
  region = "us-east-1"
}

# Get default VPC
data "aws_vpc" "default" {
  default = true
}

# Get default subnets
data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
  filter {
    name   = "default-for-az"
    values = ["true"]
  }
}

# Create a security group for the ECS service in the default VPC
resource "aws_security_group" "ldap_client_sg" {
  name        = "ldap-client-sg"
  description = "Security group for LDAP client container"
  vpc_id      = data.aws_vpc.default.id

  # SSH access on port 2222
  ingress {
    from_port   = 2222
    to_port     = 2222
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]  # Consider restricting this in production
    description = "SSH access"
  }

  # Outbound internet access
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "ldap-client-sg"
  }

  # Prevent duplicate security group creation
  lifecycle {
    create_before_destroy = true
  }
}

# Use existing cluster if it exists, otherwise create
resource "aws_ecs_cluster" "ldap_client_cluster" {
  name = "ldap-client-cluster"

  # Skip creation if cluster already exists
  lifecycle {
    ignore_changes = [
      name,
    ]
  }
}

# Use existing IAM role
data "aws_iam_role" "ecs_task_execution_role" {
  name = "ldap-client-ecs-execution-role"
}

# Use existing CloudWatch log group
data "aws_cloudwatch_log_group" "ldap_client_log_group" {
  name = "/ecs/ldap-client"
}

# Create a Task Definition for ECS
resource "aws_ecs_task_definition" "ldap_client_task" {
  family                   = "ldap-client-task"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "512"
  memory                   = "1024"
  execution_role_arn       = data.aws_iam_role.ecs_task_execution_role.arn

  container_definitions = jsonencode([
    {
      name      = "ldap-client-container"
      image     = "476114118524.dkr.ecr.us-east-1.amazonaws.com/ldap-client:latest"
      essential = true
      
      portMappings = [
        {
          containerPort = 2222
          hostPort      = 2222
          protocol      = "tcp"
        }
      ]
      
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = data.aws_cloudwatch_log_group.ldap_client_log_group.name
          "awslogs-region"        = "us-east-1"
          "awslogs-stream-prefix" = "ecs"
        }
      }
    }
  ])
}

# Create an ECS Service
resource "aws_ecs_service" "ldap_client_service" {
  name            = "ldap-client-service"
  cluster         = aws_ecs_cluster.ldap_client_cluster.id
  task_definition = aws_ecs_task_definition.ldap_client_task.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  # Prevent recreation of the service if it already exists
  lifecycle {
    create_before_destroy = true
  }

  network_configuration {
    subnets          = data.aws_subnets.default.ids
    security_groups  = [aws_security_group.ldap_client_sg.id]
    assign_public_ip = true
  }
}

# Output the instructions
output "instructions" {
  value = "LDAP client container is deployed. Check the AWS ECS Console for the public IP of the Fargate task, then connect via: ssh -p 2222 username@<public-ip>"
}