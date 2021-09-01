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
CODEGEN_DIR=$WORKSPACE_DIR/code-generator
PR_SOURCE_GH_BRANCH="dummy"
PR_TARGET_GH_BRANCH="main"
LOCAL_GIT_BRANCH="main"
GH_ORG="vijtrip2"
GH_ISSUE_REPO="ecr-controller"

# Check all the dependencies are present in container.
source "$TEST_INFRA_DIR"/scripts/lib/common.sh
check_is_installed git
check_is_installed gh

# Findout the runtime semver from the code-generator repo
cd "$CODEGEN_DIR"

ack_runtime_version=$(grep "github.com/aws-controllers-k8s/runtime" go.mod | grep -oE "v[0-9]+\.[0-9]+\.[0-9]+")
if [[ -z $ack_runtime_version ]]; then
  echo "auto-generate-controller.sh][ERROR] Unable to determine ACK runtime version from code-generator/go.mod file. Exiting."
  exit 1
else
  echo "auto-generate-controller.sh][INFO] ACK runtime version for new controllers will be $ack_runtime_version"
fi

pushd "$WORKSPACE_DIR" >/dev/null
  controller_names=$(find . -maxdepth 1 -mindepth 1 -type d | cut -d"/" -f2 | grep -E "controller$")
popd >/dev/null

for controller_name in $controller_names; do
  service_name=$(echo "$controller_name"| sed 's/-controller$//g')
  print_line_separation

  echo "auto-generate-controller.sh][INFO] ## Generating new controller for $service_name service ##"
  if [[ ! -f "$WORKSPACE_DIR/$controller_name/go.mod" ]]; then
    echo "auto-generate-controller.sh][ERROR] 'go.mod' file is missing. Skipping $controller_name."
    continue
  fi

  service_runtime_version=$(grep "github.com/aws-controllers-k8s/runtime" "$WORKSPACE_DIR/$controller_name/go.mod" | grep -oE "v[0-9]+\.[0-9]+\.[0-9]+")
  if [[ $service_runtime_version == $ack_runtime_version ]]; then
    echo "auto-generate-controller.sh][INFO] $controller_name already has the latest ACK runtime version $ack_runtime_version. Skipping $controller_name."
    continue
  fi

  echo "auto-generate-controller.sh][INFO] ACK runtime version for new controller will be $ack_runtime_version. Current version is $service_runtime_version."
  echo "auto-generate-controller.sh][INFO] Generating new controller code using command 'make build-controller'."
  export SERVICE=$service_name
  if ! make build-controller >/dev/null 2>>/tmp/"$service_name"_failure_logs; then
    cat /tmp/"$service_name"_failure_logs

    echo "auto-generate-controller.sh][ERROR] failure while executing 'build-controller' make target. Creating/Updating GitHub issue."
    issue_title="ack-bot faced problem while generating service controller for $service_name service"

    echo -n "auto-generate-controller.sh][INFO] Querying already open GH issue ... "
    issue_number=$(gh issue list -R "$GH_ORG/$GH_ISSUE_REPO" -L 1 -s open --json number -S "$issue_title" --jq '.[0].number' -A @me )
    if [[ $? -ne 0 ]]; then
      echo ""
      echo "auto-generate-controller.sh][ERROR] unable to query open github issue. Skipping $controller_name."
      continue
    fi
    echo "ok."

    if [[ -z $issue_number ]]; then
      echo -n "auto-generate-controller.sh][INFO] No open issues exist. Creating a new GitHub issue ... "
      # TODO: move the error string into issue description.
      if ! gh issue create -R "$GH_ORG/$GH_ISSUE_REPO" -t "$issue_title" -b "$issue_title . See the latest comment for error output." >/dev/null ; then
        echo ""
        echo "auto-generate-controller.sh][ERROR] Unable to create GitHub issue for reporting failure. Skipping $controller_name."
        continue
      fi
      echo "ok"

      echo -n "auto-generate-controller.sh][INFO] Sleeping for 10 seconds ... "
      sleep 10
      echo "ok"

      echo -n "auto-generate-controller.sh][INFO] Querying the issue number of newly created GitHub issue ... "
      issue_number=$(gh issue list -R "$GH_ORG/$GH_ISSUE_REPO" -L 1 -s open --json number -S "$issue_title" --jq '.[0].number' -A @me )
      if [[ $? -ne 0 || -z $issue_number ]]; then
        echo ""
        echo "auto-generate-controller.sh][ERROR] Unable to query open github issue. Skipping $controller_name."
        continue
      fi
      echo "ok"
    fi

    echo -n "auto-generate-controller.sh][INFO] Adding error output as comment in issue#$issue_number in $GH_ISSUE_REPO ... "
    if ! gh issue comment "$issue_number" -R "$GH_ORG/$GH_ISSUE_REPO" -F /tmp/"$service_name"_failure_logs >/dev/null; then
      echo ""
      echo "auto-generate-controller.sh][ERROR] Unable to add error output as issue comment. Skipping $controller_name."
      continue
    fi
    echo "ok"

    # Skip creating PR for this service controller after updating GH issue.
    continue
  fi

  pushd "$WORKSPACE_DIR/$controller_name" >/dev/null
    echo -n "auto-generate-controller.sh][INFO] Updating go.mod file in $controller_name ... "
    if ! sed -i "s|aws-controllers-k8s/runtime $service_runtime_version|aws-controllers-k8s/runtime $ack_runtime_version|" go.mod >/dev/null; then
      echo ""
      echo "auto-generate-controller.sh][ERROR] Unable to update go.mod file with latest runtime version. Skipping $controller_name."
      continue
    fi
    echo "ok"

    echo -n "auto-generate-controller.sh][INFO] Executing 'go mod tidy' to cleanup redundant dependencies for $controller_name ... "
    if ! go mod tidy >/dev/null; then
      echo ""
      echo "auto-generate-controller.sh][ERROR] Unable to execute 'go mod tidy'. Skipping $controller_name."
      continue
    fi
    echo "ok"

    git add .
    commit_message="ACK runtime update. $service_runtime_version => $ack_runtime_version"
    echo -n "auto-generate-controller.sh][INFO] Adding commit with message: '$commit_message' ... "
    if ! git commit -m "$commit_message" >/dev/null; then
      echo ""
      echo "auto-generate-controller.sh][ERROR] Failed to add commit message for $controller_name repository. Skipping $controller_name."
      continue
    fi
    echo "ok"

    echo -n "auto-generate-controller.sh][INFO] Pushing changes to branch '$PR_SOURCE_GH_BRANCH' ... "
    if ! git push --force https://$GITHUB_TOKEN@github.com/vijtrip2/$controller_name.git $LOCAL_GIT_BRANCH:$PR_SOURCE_GH_BRANCH >/dev/null 2>&1; then
      echo ""
      echo "auto-generate-controller.sh][ERROR] Failed to push the latest changes into remote repository. Skipping $controller_name."
      continue
    fi
    echo "ok"

    echo -n "auto-generate-controller.sh][INFO] Finding existing open pull requests ... "
    pr_number=$(gh pr list -R "$GH_ORG/$controller_name" -A @me -L 1 -s open --json number -S "$commit_message" --jq '.[0].number')
    if [[ $? -ne 0 ]]; then
      echo "auto-generate-controller.sh][ERROR] Failed to query for an existing pull request for $GH_ORG/$controller_name , from $PR_SOURCE_GH_BRANCH -> $PR_TARGET_GH_BRANCH branch."
    fi
    echo "ok"

    if [[ -n $pr_number ]]; then
      echo "auto-generate-controller.sh][INFO] PR#$pr_number already exists for $GH_ORG/$controller_name , from $PR_SOURCE_GH_BRANCH -> $PR_TARGET_GH_BRANCH branch."
    else
      echo -n "auto-generate-controller.sh][INFO] No Existing PRs found. Creating a new pull request for $GH_ORG/$controller_name , from $PR_SOURCE_GH_BRANCH -> $PR_TARGET_GH_BRANCH branch ... "
      if [[ ! -f /tmp/ack-bot-pr-body ]]; then
        touch /tmp/ack-bot-pr-body
        echo "$commit_message" >> /tmp/ack-bot-pr-body
        echo "By submitting this pull request, I confirm that my contribution is made under the terms of the Apache 2.0 license." >> /tmp/ack-bot-pr-body
      fi

      if ! gh pr create -R "$GH_ORG/$controller_name" -t "$commit_message" -b "$commit_message" -F /tmp/ack-bot-pr-body -H $PR_SOURCE_GH_BRANCH >/dev/null ; then
        echo ""
        echo "auto-generate-controller.sh][ERROR] Failed to create pull request. Skipping $controller_name."
        continue
      else
        echo "ok"
      fi
    fi
    echo "auto-generate-controller.sh][INFO] Done. :) "
  popd >/dev/null
done

print_line_separation
