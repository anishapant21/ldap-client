# main.tf - Deploy both LDAP client containers

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

# Create a security group for the ECS services in the default VPC
resource "aws_security_group" "ldap_clients_sg" {
  name        = "ldap-clients-sg"
  description = "Security group for LDAP client containers"
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
    Name = "ldap-clients-sg"
  }

  # Prevent duplicate security group creation
  lifecycle {
    create_before_destroy = true
  }
}

# Use existing cluster if it exists, otherwise create
resource "aws_ecs_cluster" "ldap_cluster" {
  name = "ldap-clients-cluster"

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

# Use existing CloudWatch log group or create if doesn't exist
resource "aws_cloudwatch_log_group" "ldap_client1_log_group" {
  name              = "/ecs/ldap-client-1"
  retention_in_days = 30
}

resource "aws_cloudwatch_log_group" "ldap_client2_log_group" {
  name              = "/ecs/ldap-client-2"
  retention_in_days = 30
}

# Create Task Definition for first LDAP client
resource "aws_ecs_task_definition" "ldap_client1_task" {
  family                   = "ldap-client1-task"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "512"
  memory                   = "1024"
  execution_role_arn       = data.aws_iam_role.ecs_task_execution_role.arn

  container_definitions = jsonencode([
    {
      name      = "ldap-client1-container"
      image     = var.image_client1
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
          "awslogs-group"         = aws_cloudwatch_log_group.ldap_client1_log_group.name
          "awslogs-region"        = "us-east-1"
          "awslogs-stream-prefix" = "ecs"
        }
      }
    }
  ])
}

# Create Task Definition for second LDAP client
resource "aws_ecs_task_definition" "ldap_client2_task" {
  family                   = "ldap-client2-task"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "512"
  memory                   = "1024"
  execution_role_arn       = data.aws_iam_role.ecs_task_execution_role.arn

  container_definitions = jsonencode([
    {
      name      = "ldap-client2-container"
      image     = var.image_client2
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
          "awslogs-group"         = aws_cloudwatch_log_group.ldap_client2_log_group.name
          "awslogs-region"        = "us-east-1"
          "awslogs-stream-prefix" = "ecs"
        }
      }
    }
  ])
}

# Create an ECS Service for first client
resource "aws_ecs_service" "ldap_client1_service" {
  name            = "ldap-client1-service"
  cluster         = aws_ecs_cluster.ldap_cluster.id
  task_definition = aws_ecs_task_definition.ldap_client1_task.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  # Prevent recreation of the service if it already exists
  lifecycle {
    create_before_destroy = true
  }

  network_configuration {
    subnets          = [tolist(data.aws_subnets.default.ids)[0]]
    security_groups  = [aws_security_group.ldap_clients_sg.id]
    assign_public_ip = true
  }
}

# Create an ECS Service for second client
resource "aws_ecs_service" "ldap_client2_service" {
  name            = "ldap-client2-service"
  cluster         = aws_ecs_cluster.ldap_cluster.id
  task_definition = aws_ecs_task_definition.ldap_client2_task.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  # Prevent recreation of the service if it already exists
  lifecycle {
    create_before_destroy = true
  }

  network_configuration {
    subnets          = [tolist(data.aws_subnets.default.ids)[0]]
    security_groups  = [aws_security_group.ldap_clients_sg.id]
    assign_public_ip = true
  }
}

# Output the instructions
output "instructions" {
  value = <<-EOT
    Both LDAP client containers are deployed:
    
    Client 1: Check the AWS ECS Console for the public IP of the "ldap-client1-service" task
    Client 2: Check the AWS ECS Console for the public IP of the "ldap-client2-service" task
    
    Connect to either via: ssh -p 2222 username@<public-ip>
  EOT
}