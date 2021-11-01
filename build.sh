#!/bin/bash
set -e

# Preparing the variables to be used by "docker build".
VARS=$(env | awk -F = '/^BUILD_ENV_/ {print $1}')
BUILD_ARGS=""
for var_name in ${VARS}
do
  NAME=$(echo $var_name | sed 's/BUILD_ENV_//g')
  BUILD_ARGS="$BUILD_ARGS --build-arg $NAME=\"\${$var_name}\""
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

echo "::group::Build args"
echo $BUILD_ARGS
echo "::endgroup::"


COMMIT_MESSAGE=`git log --format=%B -n 1 HEAD`

if [[ "$COMMIT_MESSAGE" =~ ^\[skip-build\] || "$SKIP_BUILD" == "Y" ]]; then
  echo "Build skipped!"
else
  echo "::group::Checking cache"
  if [[ "$ENABLE_CACHE" == "Y" || "$ENABLE_CACHE" == "" ]]; then
    if [[ "$TAG" =~ ^production ]]; then
      CACHE_TO="production"
    else
      CACHE_TO=$TAG
    fi

    CACHE=" \
      --output type=image,name=$REPO_URI:$TAG,push=true \
      --cache-from=type=registry,ref=ghcr.io/$GITHUB_REPOSITORY:production \
      --cache-from=type=registry,ref=ghcr.io/$GITHUB_REPOSITORY:$TAG \
      --cache-to=type=registry,ref=ghcr.io/$GITHUB_REPOSITORY:$CACHE_TO,mode=max"

    echo $GITHUB_TOKEN | docker login ghcr.io -u $GITHUB_ACTOR --password-stdin

    docker context create tls-environment

    docker buildx create \
      --name cache-builder \
      --driver docker-container \
      --buildkitd-flags '\
      --allow-insecure-entitlement security.insecure \
      --allow-insecure-entitlement network.host' \
      --use tls-environment

    echo "Cache ativado"
  else
    CACHE=""
    echo "Cache desativado"
  fi
  echo "::endgroup::"

  echo "::group::Build and push the image to ECR"
  bash -c "docker buildx build --push \
    $CACHE \
    -f $DOCKERFILE -t $REPO_URI:$TAG $BUILD_ARGS ."
  echo "::endgroup::"
fi

echo "REPOSITORY_URI=$REPO_URI" >> $GITHUB_ENV
echo "IMAGE_TAG=$TAG" >> $GITHUB_ENV

echo "Success!"
