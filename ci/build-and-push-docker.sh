#!/bin/bash
set -e

if [ -z "$AWS_REGION" ]; then
  echo "AWS_REGION is not set"
  exit 1
fi

if [ -z "$AWS_ACCOUNT_ID" ]; then
  echo "AWS_ACCOUNT_ID is not set"
  exit 1
fi

if [ -z "$ECR_REPO_NAME" ]; then
  echo "ECR_REPO_NAME is not set"
  exit 1
fi

IMAGE_TAG=${GITHUB_SHA:-"latest"}
DOCKER_CONTEXT=${DOCKER_CONTEXT:-"./docker"}

ECR_URL="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${ECR_REPO_NAME}"

echo "Building Docker image..."
docker build -t ${ECR_REPO_NAME}:${IMAGE_TAG} "${DOCKER_CONTEXT}"

echo "Tagging image for ECR..."
docker tag ${ECR_REPO_NAME}:${IMAGE_TAG} ${ECR_URL}:${IMAGE_TAG}

echo "Pushing image to ECR..."
docker push ${ECR_URL}:${IMAGE_TAG}

echo "Image pushed: ${ECR_URL}:${IMAGE_TAG}"
