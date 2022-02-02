#!/bin/bash
set -e

# Preparing the variables to be used by "docker build".
vars=$(env | awk -F = '/^BUILD_ENV_/ {print $1}')

repo_uri=""
repo_uri_ecr () {
  repo_uri=$(aws ecr describe-repositories \
      --repository-names "${REPOSITORY}" \
      --query "repositories[0].repositoryUri" \
      --output text 2>/dev/null || \
  aws ecr create-repository \
      --repository-name "${REPOSITORY}"  \
      --query "repository.repositoryUri" \
      --output text)
}

build_args=""
build_docker_args () {
  for var_name in ${vars}
  do
    NAME=$(echo $var_name | sed 's/BUILD_ENV_//g')
    build_args="$build_args --build-arg $NAME=\"\${$var_name}\""
  done
  echo $build_args
}

cache_args=""
enable_cache () {
  echo $GITHUB_TOKEN | docker login ghcr.io -u $GITHUB_ACTOR --password-stdin

  docker context create tls-environment

  docker buildx create \
    --name cache-builder \
    --driver docker-container \
    --buildkitd-flags '\
    --allow-insecure-entitlement security.insecure \
    --allow-insecure-entitlement network.host' \
    --use tls-environment

  echo "Cache ativado."
}

build_push_img_to_ecr () {
  echo "::group::Build and push the image to ECR"

  cache_to=$TAG
  if [[ "$TAG" =~ ^production ]]; then
    cache_to="production"
  fi

  cache_args=" \
    --output type=image,name=$repo_uri:$TAG,push=true \
    --cache-from=type=registry,ref=ghcr.io/$GITHUB_REPOSITORY:production \
    --cache-from=type=registry,ref=ghcr.io/$GITHUB_REPOSITORY:$TAG \
    --cache-to=type=registry,ref=ghcr.io/$GITHUB_REPOSITORY:$cache_to,mode=max"

  bash -c "docker buildx build --push \
    $cache_args \
    -f $DOCKERFILE -t $repo_uri:$TAG $build_args ."
  echo "::endgroup::"
}

build () {
  echo "::group::Checking cache"
  if [[ "$ENABLE_CACHE" == "Y" || "$ENABLE_CACHE" == "" ]]; then
    enable_cache
  else
    echo "Cache desativado."
  fi
  echo "::endgroup::"

  build_push_img_to_ecr
}

## EXEC

echo "Checking if the repository exists on ECR..."
repo_uri_ecr
echo "URI: $repo_uri"

echo "::group::Build args"
build_docker_args
echo "::endgroup::"

commit_message=`git log --format=%B -n 1 HEAD`
if [[ "$commit_message" =~ ^\[skip-build\] || "$SKIP_BUILD" == "Y" ]]; then
  echo "Build skipped!"
else
  build
fi

echo "REPOSITORY_URI=$repo_uri" >> $GITHUB_ENV
echo "IMAGE_TAG=$TAG" >> $GITHUB_ENV

echo "Success!"
