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

#!/usr/bin/env bash
echo "--- docker command lookup ---"
which docker
type -a docker
declare -f docker || echo "🍂 no docker function defined"
echo

echo "--- inspect CLI plugins ---"
ls -lah "$HOME/.docker/cli-plugins" 2>/dev/null || echo "🍂 no user cli-plugins dir"
ls -lah /usr/libexec/docker/cli-plugins 2>/dev/null || echo "🍂 no system cli-plugins dir"
echo

echo "--- docker & buildx versions ---"
docker --version
docker buildx version || echo "🍂 buildx plugin not found"
echo

echo "--- existing builders ---"
docker buildx ls || echo "🍂 no builders"
echo

echo "--- env DOCKER_* ---"
env | grep -i '^DOCKER_' || echo "🍂 no DOCKER_* vars"
echo

echo "--- check for CRLF in this script ---"
grep -nUa $'\r' "${BASH_SOURCE[0]}" && echo "⚠️ CRLFs found" || echo "🍂 no CRLFs"
echo

echo "Docker context: ${DOCKER_CONTEXT:-./docker}"
echo "Current directory: $(pwd)"
echo "Listing docker/ dir:"
ls -lah ./docker
echo

echo "Building Docker image…"
docker build -t "${ECR_REPO_NAME}:${IMAGE_TAG}" "${DOCKER_CONTEXT}"

echo "Tagging image for ECR..."
docker tag ${ECR_REPO_NAME}:${IMAGE_TAG} ${ECR_URL}:${IMAGE_TAG}

echo "Pushing image to ECR..."
docker push ${ECR_URL}:${IMAGE_TAG}

echo "Image pushed: ${ECR_URL}:${IMAGE_TAG}"
