#!/bin/bash
set -euo pipefail

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


# ——— CONFIGURATION —————————————————————————
AWS_ACCOUNT_ID=${AWS_ACCOUNT_ID:?Need AWS_ACCOUNT_ID}
AWS_REGION=${AWS_REGION:-us-east-1}
ECR_REPO_NAME=${ECR_REPO_NAME:?Need ECR_REPO_NAME}

# Tag by Git SHA (first 7 chars), fallback to “latest”
GIT_SHA=$(git rev-parse --short=7 HEAD)
IMAGE_TAG=${GIT_SHA:-latest}
BUILD_CONTEXT=${BUILD_CONTEXT:-"./docker"}

# Full ECR repo URI
REPO_URI="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${ECR_REPO_NAME}"
# ——————————————————————————————————————————

echo "→ Logging into ECR"
aws ecr get-login-password --region "${AWS_REGION}" \
  | docker login --username AWS --password-stdin "${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"

echo "→ Ensuring ECR repo exists"
aws ecr describe-repositories --repository-names "${ECR_REPO_NAME}" \
  --region "${AWS_REGION}" >/dev/null 2>&1 || \
  aws ecr create-repository --repository-name "${ECR_REPO_NAME}" --region "${AWS_REGION}"

echo "→ Building image ${REPO_URI}:${IMAGE_TAG}"
docker build \
  --file "${BUILD_CONTEXT}/Dockerfile" \
  --tag "${REPO_URI}:${IMAGE_TAG}" \
  "${BUILD_CONTEXT}/"

echo "→ Pushing to ECR"
docker push "${REPO_URI}:${IMAGE_TAG}"

echo "✅ Build and push complete: ${REPO_URI}:${IMAGE_TAG}"

echo "Image pushed: ${ECR_URL}:${IMAGE_TAG}"
