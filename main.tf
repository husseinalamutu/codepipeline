# Provider configuration for AWS
provider "aws" {
  region = "us-west-2" # Update with your desired region
}

# Create an S3 bucket for artifact storage
resource "aws_s3_bucket" "my_bucket" {
  bucket = "alamz-artifact-bucket" # Update with a unique bucket name
}
# resource "aws_s3_bucket_acl" "example" {
#   bucket = aws_s3_bucket.my_bucket.id
#   acl    = "private"
# }
# Create an IAM role for the pipeline
resource "aws_iam_role" "my_role" {
  name = "my-pipeline-role"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "codepipeline.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF
}

# Create a CodeStar source connection
resource "aws_codestarconnections_connection" "my_source_connection" {
  name = "my-source-connection"
  provider_type    = "GitHub"
  tags = {
    Name = "my-source-connection"
  }
}

resource "aws_ecs_task_definition" "my_task_definition" {
  family                   = "my-task-definition-family"
  execution_role_arn       = aws_iam_role.my_task_execution_role.arn
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu = 256
  memory = 512
  container_definitions = <<DEFINITION
[
  {
    "name": "my-container",
    "image": "${aws_ecr_repository.my_ecr_repository.repository_url}:latest",
    "essential": true,
    "portMappings": [
      {
        "containerPort": 80,
        "protocol": "tcp"
      }
    ]
  }
]
DEFINITION
}

resource "aws_iam_role" "my_task_execution_role" {
  name               = "my-task-execution-role"
  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "ecs-tasks.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF
}

resource "aws_iam_role_policy_attachment" "my_task_execution_role_policy_attachment" {
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
  role       = aws_iam_role.my_task_execution_role.name
}

# Create an IAM role for CodeBuild
resource "aws_iam_role" "codebuild_role" {
  name = "codebuild-service-role"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "codebuild.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF

  # Attach necessary policies to the role
  # ...

  tags = {
    Name = "codebuild-service-role"
  }
}

# Create an IAM role policy for CodeBuild (example)
resource "aws_iam_role_policy" "codebuild_policy" {
  name = "codebuild-service-policy"
  role = aws_iam_role.codebuild_role.name

  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": "ecr:*",
      "Resource": "*"
    },
    {
      "Effect": "Allow",
      "Action": "ecs:*",
      "Resource": "*"
    },
    {
      "Effect": "Allow",
      "Action": "iam:PassRole",
      "Resource": "*"
    }
  ]
}
EOF
}


# Create an ECS cluster
resource "aws_ecs_cluster" "my_cluster" {
  name = "my-ecs-cluster"
}

# Create an ECS service
resource "aws_ecs_service" "my_service" {
  name            = "my-ecs-service"
  cluster         = aws_ecs_cluster.my_cluster.id
  task_definition = aws_ecs_task_definition.my_task_definition.arn
  desired_count   = 2 
  network_configuration {
    security_groups = [aws_security_group.my_security_group.id]
    subnets         = [aws_subnet.my_subnet.id]
  }
}

# Create a CodePipeline
resource "aws_codepipeline" "my_pipeline" {
  name     = "my-pipeline"
  role_arn = aws_iam_role.my_role.arn

  artifact_store {
    location = aws_s3_bucket.my_bucket.bucket
    type     = "S3"
  }

  stage {
    name = "Source"

    action {
      name             = "SourceAction"
      category         = "Source"
      owner            = "AWS"
      provider         = "CodeStarSourceConnection"
      version          = "1"
      output_artifacts = ["source_output"]

      configuration = {
        BranchName       = "main"
        ConnectionArn    = aws_codestarconnections_connection.my_source_connection.arn
        FullRepositoryId = "https://github.com/husseinalamutu/docker-cp.git"
      }
    }
  }

  stage {
    name = "Build"

    action {
      name             = "BuildAction"
      category         = "Build"
      owner            = "AWS"
      provider         = "CodeBuild"
      version          = "1"
      input_artifacts  = ["source_output"]
      output_artifacts = ["build_output"]

      configuration = {
        ProjectName = aws_codebuild_project.my_codebuild_project.name
      }
    }
  }

  stage {
    name = "Deploy"

    action {
      name            = "DeployAction"
      category        = "Deploy"
      owner           = "AWS"
      provider        = "ECS"
      version         = "1"
      input_artifacts = ["build_output"]

      configuration = {
        ClusterName        = aws_ecs_cluster.my_cluster.name
        ServiceName        = aws_ecs_service.my_service.name
        FileName           = "imagedefinitions.json"
        Image1ArtifactName = "build_output"
        ActionMode         = "REPLACE_ON_FAILURE"
      }
    }
  }
}

resource "aws_ecr_repository" "my_ecr_repository" {
  name = "my-ecr-repository"
}

# Create a CodeBuild project
resource "aws_codebuild_project" "my_codebuild_project" {
  name         = "my-codebuild-project"
  description  = "CodeBuild project for building Docker image"
  service_role = aws_iam_role.codebuild_role.arn
  artifacts {
    type = "NO_ARTIFACTS"
  }
  environment {
    compute_type = "BUILD_GENERAL1_SMALL"
    image        = "aws/codebuild/standard:4.0"
    type         = "LINUX_CONTAINER"
    environment_variable {
      name  = "ECR_REPOSITORY_URI"
      value = aws_ecr_repository.my_ecr_repository.repository_url
    }
  }
  source {
    type            = "GITHUB"
    location        = "https://github.com/husseinalamutu/docker-cp.git"
    git_clone_depth = 1
    buildspec       = var.buildspec
  }
  tags = {
    Name = "my-codebuild-project"
  }
}