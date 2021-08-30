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

echo "I am gonna generate the heckin controllers ... "