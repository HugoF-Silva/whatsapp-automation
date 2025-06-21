#!/bin/bash
set -e

# ----- CONFIG -----
AWS_REGION=${AWS_REGION:-us-east-1}
AWS_ACCOUNT_ID=${AWS_ACCOUNT_ID:-123456789012}
ECR_REPO_NAME=${ECR_REPO_NAME:-evolutionapi}
IMAGE_TAG=${GITHUB_SHA:-latest}
DOCKER_CONTEXT=${DOCKER_CONTEXT:-./docker}

# ECR URL
ECR_URL="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${ECR_REPO_NAME}"

echo "Building Docker image..."
docker build -t ${ECR_REPO_NAME}:${IMAGE_TAG} "${DOCKER_CONTEXT}"

echo "Tagging image for ECR..."
docker tag ${ECR_REPO_NAME}:${IMAGE_TAG} ${ECR_URL}:${IMAGE_TAG}

echo "Pushing image to ECR..."
docker push ${ECR_URL}:${IMAGE_TAG}

echo "Image pushed: ${ECR_URL}:${IMAGE_TAG}"
