#!/usr/bin/env bash

set -eo pipefail

USAGE="
Usage:
  $(basename "$0")
"

# Important Directory references based on prowjob configuration.
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
SCRIPTS_DIR=$DIR
CD_DIR=$DIR/..
TEST_INFRA_DIR=$CD_DIR/..
WORKSPACE_DIR=$TEST_INFRA_DIR/..

# Check all the dependencies are present in container.
source "$TEST_INFRA_DIR"/scripts/lib/common.sh
check_is_installed git

echo "auto-generate-controller.sh][INFO] I am gonna generate the heckin controllers ... "

cd "$WORKSPACE_DIR"
# List all the controller names.
controller_names=$(find . -maxdepth 1 -mindepth 1 -type d | cut -d"/" -f2 | grep -E "controller$")
for controller_name in $controller_names; do
  pushd "$WORKSPACE_DIR/$controller_name" >/dev/null
    echo "=========================================="
    echo "$controller_name"
    git status
    echo "=========================================="
  popd >/dev/null
done
echo "auto-generate-controller.sh][INFO] Finished printing the git status for all the controllers."

echo "auto-generate-controller.sh][INFO] GH TOKEN: $GITHUB_TOKEN"
echo "auto-generate-controller.sh][INFO] GH ACTOR: $GITHUB_ACTOR"

gh issue list -R aws-controllers-k8s/community

echo "auto-generate-controller.sh][INFO] finished printing issues using github cli"
