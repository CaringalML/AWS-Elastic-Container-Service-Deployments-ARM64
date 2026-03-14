resource "aws_db_subnet_group" "db_subnet_group" {
  name       = "${var.project_name}-db-subnet-group"
  subnet_ids = aws_subnet.private[*].id
  tags = {
    Project     = var.project_name
    Environment = var.environment
  }
}

resource "aws_db_parameter_group" "db_params" {
  name        = "${var.project_name}-db-params"
  family      = "postgres15"
  description = "Parameter group for ${var.project_name} RDS"
  tags = {
    Project     = var.project_name
    Environment = var.environment
  }
}

resource "aws_db_instance" "db_instance" {
  identifier              = "${var.project_name}-db"
  engine                  = "postgres"
  engine_version          = "15"
  instance_class          = "db.t4g.micro"
  allocated_storage       = 20
  db_name                 = var.db_database
  username                = var.db_username
  password                = var.db_password
  port                    = var.db_port
  db_subnet_group_name    = aws_db_subnet_group.db_subnet_group.name
  vpc_security_group_ids  = [aws_security_group.db_sg.id]
  skip_final_snapshot     = var.skip_final_snapshot
  publicly_accessible     = false
  multi_az                = true
  storage_encrypted       = true
  apply_immediately       = true
  parameter_group_name    = aws_db_parameter_group.db_params.name
  tags = {
    Project     = var.project_name
    Environment = var.environment
  }
}

resource "aws_security_group" "db_sg" {
  name        = "${var.project_name}-db-sg"
  description = "Allow DB access from ECS only"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port   = var.db_port
    to_port     = var.db_port
    protocol    = "tcp"
    security_groups = [aws_security_group.ecs_tasks.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Project     = var.project_name
    Environment = var.environment
  }
}
