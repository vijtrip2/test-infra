#!/usr/bin/env bash

set -eox pipefail

USAGE="
Usage:
  $(basename "$0")

Publishes the Docker image and helm chart for an ACK service controller. By default, the
repository will be $DEFAULT_DOCKER_REPOSITORY and the image tag for the specific ACK
service controller will be ":\$SERVICE-\$VERSION".

<AWS_SERVICE> AWS Service name (ecr, sns, sqs)

Example:
export DOCKER_REPOSITORY=aws-controllers-k8s
$(basename "$0") ecr

Environment variables:
  DOCKER_REPOSITORY:        Name for the Docker repository to push to
                            Default: $DEFAULT_DOCKER_REPOSITORY
  AWS_SERVICE_DOCKER_IMG:   Controller container image tag
                            Default: aws-controllers-k8s:$AWS_SERVICE-$VERSION
  QUIET:                            Build controller container image quietly (<true|false>)
                                    Default: false
"

# find out the service name and semver tag from the prow environment variables.
AWS_SERVICE=$(echo "$REPO_NAME" | rev | cut -d"-" -f2- | rev | tr '[:upper:]' '[:lower:]')
VERSION=$PULL_BASE_REF
#AWS_SERVICE=$(echo "$SERVICE" | tr '[:upper:]' '[:lower:]')


# Important Directory references
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
SCRIPTS_DIR=$DIR
CD_DIR=$DIR/..
TEST_INFRA_DIR=$CD_DIR/..
WORKSPACE_DIR=$TEST_INFRA_DIR/..
SERVICE_CONTROLLER_DIR="$WORKSPACE_DIR/$AWS_SERVICE-controller"
#ROOT_DIR=/


# Check all the dependencies are present in container.
source "$SCRIPTS_DIR"/lib/common.sh

check_is_installed buildah
check_is_installed aws
check_is_installed helm

# Setup the destination repository for docker and helm
perform_buildah_and_helm_login

# Determine parameters for docker-build command
pushd "$WORKSPACE_DIR"/"$AWS_SERVICE"-controller 1>/dev/null

#export DOCKER_BUILDKIT=${DOCKER_BUILDKIT:-1}
#VERSION=${VERSION:-$(git describe --tags --always --dirty || echo "unknown")}
SERVICE_CONTROLLER_GIT_COMMIT=$(git rev-parse HEAD)
QUIET=${QUIET:-"false"}
BUILD_DATE=$(date +%Y-%m-%dT%H:%M)
CONTROLLER_IMAGE_DOCKERFILE_PATH=$CD_DIR/controller/Dockerfile

DEFAULT_DOCKER_REPOSITORY="public.ecr.aws/aws-controllers/controllers"
DOCKER_REPOSITORY=${DOCKER_REPOSITORY:-"$DEFAULT_DOCKER_REPOSITORY"}
DEFAULT_AWS_SERVICE_DOCKER_IMG_TAG="${AWS_SERVICE}-${VERSION}-do-not-use"
AWS_SERVICE_DOCKER_IMG_TAG=${AWS_SERVICE_DOCKER_IMG_TAG:-"$DEFAULT_AWS_SERVICE_DOCKER_IMG_TAG"}
AWS_SERVICE_DOCKER_IMG=${AWS_SERVICE_DOCKER_IMG:-"$DOCKER_REPOSITORY:$AWS_SERVICE_DOCKER_IMG_TAG"}
DOCKER_BUILD_CONTEXT="$WORKSPACE_DIR"

popd 1>/dev/null

cd "$WORKSPACE_DIR"

if [[ $QUIET = "false" ]]; then
    echo "building '$AWS_SERVICE' controller docker image with tag: ${AWS_SERVICE_DOCKER_IMG}"
    echo " git commit: $SERVICE_CONTROLLER_GIT_COMMIT"
fi

echo "AWS_SERVICE_DOCKER_IMG: $AWS_SERVICE_DOCKER_IMG"
echo "DOCKERFILE: $CONTROLLER_IMAGE_DOCKERFILE_PATH"
echo "AWS_SERVICE: $AWS_SERVICE"
echo "SERVICE_CONTROLLER_GIT_VERSION: $VERSION"
echo "SERVICE_CONTROLLER_GIT_COMMIT: $SERVICE_CONTROLLER_GIT_COMMIT"
echo "DOCKER_BUILD_CONTEXT: $DOCKER_BUILD_CONTEXT"

#buildah bud \
#  --quiet="$QUIET" \
#  -t "$AWS_SERVICE_DOCKER_IMG" \
#  -f "$CONTROLLER_IMAGE_DOCKERFILE_PATH" \
#  --build-arg service_alias="$AWS_SERVICE" \
#  --build-arg service_controller_git_version="$VERSION" \
#  --build-arg service_controller_git_commit="$SERVICE_CONTROLLER_GIT_COMMIT" \
#  --build-arg build_date="$BUILD_DATE" \
#  "${DOCKER_BUILD_CONTEXT}"
#
#if [ $? -ne 0 ]; then
#  exit 2
#fi
#
#echo "Pushing '$AWS_SERVICE' controller image with tag: ${AWS_SERVICE_DOCKER_IMG_TAG}"
#
#buildah push "${AWS_SERVICE_DOCKER_IMG}"
#
#if [ $? -ne 0 ]; then
#  exit 2
#fi
#
#DEFAULT_HELM_REGISTRY="public.ecr.aws/aws-controllers-k8s"
#DEFAULT_HELM_REPO="chart"
#DEFAULT_RELEASE_VERSION="unknown"
#
#HELM_REGISTRY=${HELM_REGISTRY:-$DEFAULT_HELM_REGISTRY}
#HELM_REPO=${HELM_REPO:-$DEFAULT_HELM_REPO}
#
#export HELM_EXPERIMENTAL_OCI=1
#
#if [[ -d "$SERVICE_CONTROLLER_DIR/helm" ]]; then
#    echo -n "Generating Helm chart package for $AWS_SERVICE@$VERSION ... "
#    helm chart save "$SERVICE_CONTROLLER_DIR"/helm/ "$HELM_REGISTRY/$HELM_REPO:$AWS_SERVICE-$VERSION"
#    echo "ok."
#    helm chart push "$HELM_REGISTRY/$HELM_REPO:$AWS_SERVICE-$VERSION"
#else
#    echo "Error building Helm packages:" 1>&2
#    echo "$SERVICE_CONTROLLER_SOURCE_PATH/helm is not a directory." 1>&2
#    echo "${USAGE}"
#    exit 1
#fi
