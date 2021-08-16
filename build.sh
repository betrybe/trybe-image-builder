#!/bin/sh
set -e

# Preparing the variables to be used by "docker build".
VARS=$(env | grep ^$PREFIX | sed 's/'$PREFIX'//g')
BUILD_ARGS=""
for path in ${VARS}
do
  BUILD_ARGS="$BUILD_ARGS --build-arg $path"
done

echo "Checking if the repository exists on ECR..."
REPO_URI=$(aws ecr describe-repositories \
    --repository-names "${REPOSITORY}" \
    --query "repositories[0].repositoryUri" \
    --output text 2>/dev/null || \
aws ecr create-repository \
    --repository-name "${REPOSITORY}"  \
    --query "repository.repositoryUri" \
    --output text)
echo "URI: $REPO_URI"

echo $BUILD_ARGS

echo "Building the image..."
docker build . -f $DOCKERFILE -t $REPO_URI:$TAG $BUILD_ARGS

echo "Pushing the image to ECR..."
docker push $REPO_URI:$TAG

echo "Success!"
