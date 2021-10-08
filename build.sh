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

if [[ "$COMMIT_MESSAGE" =~ "^\[skip-build\]" || "$SKIP_BUILD" == "Y" ]]; then
  echo "Build skipped!"
else
  echo "::group::Build and push the image to ECR"
  bash -c "docker build . --push --cache-from=type=registry,ref=$REPO_URI:$TAG --cache-to=type=registry,ref=$REPO_URI:$TAG -f $DOCKERFILE -t $REPO_URI:$TAG $BUILD_ARGS"
  echo "::endgroup::"
fi

echo "REPOSITORY_URI=$REPO_URI" >> $GITHUB_ENV
echo "IMAGE_TAG=$TAG" >> $GITHUB_ENV

echo "Success!"
