# Provider configuration for AWS
provider "aws" {
  region = "us-west-2"  # Update with your desired region
}

# Create an S3 bucket for artifact storage
resource "aws_s3_bucket" "my_bucket" {
  bucket = "my-artifact-bucket"  # Update with a unique bucket name
  acl    = "private"
}

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
  provider_type    = "GitHub"
  connection_name  = "my-source-connection"
  owner_account_id = "<AWS account ID>"
  provider_details = {
    "accessToken" = "<GitHub personal access token>"
  }
  tags = {
    Name = "my-source-connection"
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
      name            = "SourceAction"
      category        = "Source"
      owner           = "AWS"
      provider        = "CodeStarSourceConnection"
      version         = "1"
      output_artifacts = ["source_output"]

      configuration = {
        BranchName = "main"
        ConnectionArn = aws_codestarconnections_connection.my_source_connection.arn
        FullRepositoryId = "<GitHub repository ID>"
      }
    }
  }

  stage {
    name = "Build"

    action {
      name            = "BuildAction"
      category        = "Build"
      owner           = "AWS"
      provider        = "CodeBuild"
      version         = "1"
      input_artifacts = ["source_output"]
      output_artifacts = ["build_output"]

      configuration = {
        ProjectName = "<CodeBuild project name>"
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
        ClusterName       = "<ECS cluster name>"
        ServiceName       = "<ECS service name>"
        FileName          = "imagedefinitions.json"
        Image1ArtifactName  = "build_output"
        ActionMode        = "REPLACE_ON_FAILURE"
      }
    }
  }
}

# Create a CodeBuild project
resource "aws_codebuild_project" "my_codebuild_project" {
  name          = "my-codebuild-project"
  description   = "CodeBuild project for building Docker image"
  service_role  = "<CodeBuild service role ARN>"
  artifacts {
    type = "NO_ARTIFACTS"
  }
  environment {
    compute_type                = "BUILD_GENERAL1_SMALL"
    image                       = "aws/codebuild/standard:4.0"
    type                        = "LINUX_CONTAINER"
    environment_variable {
      name  = "ECR_REPOSITORY_URI"
      value = "<ECR repository URI>"
    }
  }
  source {
    type            = "GITHUB"
    location        = "<GitHub repository HTTPS URL>"
    git_clone_depth = 1
    buildspec       = <<EOF
version: 0.2
phases:
  install:
    runtime-versions:
      docker: 20
  pre_build:
    commands:
      - echo Logging in to Amazon ECR...
      - aws ecr get-login-password --region ${AWS_REGION} | docker login --username AWS --password-stdin ${ECR_REPOSITORY_URI}
  build:
    commands:
      - echo Building the Docker image...
      - docker build -t ${ECR_REPOSITORY_URI}:latest .
  post_build:
    commands:
      - echo Pushing the Docker image to Amazon ECR...
      - docker push ${ECR_REPOSITORY_URI}:latest
EOF
  }
  tags = {
    Name = "my-codebuild-project"
  }
}
