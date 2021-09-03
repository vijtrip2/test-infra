#!/usr/bin/env bash

set -eo pipefail

USAGE="
Usage:
  $(basename "$0")
"

# Important Directory references based on prowjob configuration.
THIS_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
SCRIPTS_DIR=$THIS_DIR
CD_DIR=$THIS_DIR/..
TEST_INFRA_DIR=$CD_DIR/..
WORKSPACE_DIR=$TEST_INFRA_DIR/..
CODEGEN_DIR=$WORKSPACE_DIR/code-generator
PR_SOURCE_GH_BRANCH="dummy"
PR_TARGET_GH_BRANCH="main"
LOCAL_GIT_BRANCH="main"
GH_ORG="vijtrip2"
GH_ISSUE_REPO="ecr-controller"
GITHUB_NO_REPLY_EMAIL_PREFIX="82905295+ack-bot@users.noreply.github.com"

# Check all the dependencies are present in container.
source "$TEST_INFRA_DIR"/scripts/lib/common.sh
check_is_installed git
check_is_installed gh

user_email="${GITHUB_ACTOR}@users.noreply.${GITHUB_DOMAIN:-"github.com"}"
if [ -n "${GITHUB_NO_REPLY_EMAIL_PREFIX}" ]; then
    user_email="${GITHUB_NO_REPLY_EMAIL_PREFIX}+${user_email}"
fi

git config --global user.name "${GITHUB_ACTOR}" >/dev/null
git config --global user.email "${user_email}" >/dev/null

# Findout the runtime semver from the code-generator repo
cd "$CODEGEN_DIR"

ACK_RUNTIME_VERSION=$(grep "github.com/aws-controllers-k8s/runtime" go.mod | grep -oE "v[0-9]+\.[0-9]+\.[0-9]+")
if [[ -z $ACK_RUNTIME_VERSION ]]; then
  echo "auto-generate-controller.sh][ERROR] Unable to determine ACK runtime version from code-generator/go.mod file. Exiting."
  exit 1
else
  echo "auto-generate-controller.sh][INFO] ACK runtime version for new controllers will be $ACK_RUNTIME_VERSION"
fi

pushd "$WORKSPACE_DIR" >/dev/null
  CONTROLLER_NAMES=$(find . -maxdepth 1 -mindepth 1 -type d | cut -d"/" -f2 | grep -E "controller$")
popd >/dev/null

for CONTROLLER_NAME in $CONTROLLER_NAMES; do
  SERVICE_NAME=$(echo "$CONTROLLER_NAME"| sed 's/-controller$//g')
  print_line_separation

  echo "auto-generate-controller.sh][INFO] ## Generating new controller for $SERVICE_NAME service ##"
  if [[ ! -f "$WORKSPACE_DIR/$CONTROLLER_NAME/go.mod" ]]; then
    echo "auto-generate-controller.sh][ERROR] 'go.mod' file is missing. Skipping $CONTROLLER_NAME."
    continue
  fi

  SERVICE_RUNTIME_VERSION=$(grep "github.com/aws-controllers-k8s/runtime" "$WORKSPACE_DIR/$CONTROLLER_NAME/go.mod" | grep -oE "v[0-9]+\.[0-9]+\.[0-9]+")
  if [[ $SERVICE_RUNTIME_VERSION == $ACK_RUNTIME_VERSION ]]; then
    echo "auto-generate-controller.sh][INFO] $CONTROLLER_NAME already has the latest ACK runtime version $ACK_RUNTIME_VERSION. Skipping $CONTROLLER_NAME."
    continue
  fi

  echo "auto-generate-controller.sh][INFO] ACK runtime version for new controller will be $ACK_RUNTIME_VERSION. Current version is $SERVICE_RUNTIME_VERSION."
  echo "auto-generate-controller.sh][INFO] Generating new controller code using command 'make build-controller'."
  export SERVICE=$SERVICE_NAME
  MAKE_BUILD_OUTPUT_FILE=/tmp/"$SERVICE_NAME"_make_build_output
  MAKE_BUILD_ERROR_FILE=/tmp/"$SERVICE_NAME"_make_build_error
  if ! make build-controller > "$MAKE_BUILD_OUTPUT_FILE" 2>"$MAKE_BUILD_ERROR_FILE"; then
    cat "$MAKE_BUILD_ERROR_FILE"

    echo "auto-generate-controller.sh][ERROR] failure while executing 'make build-controller' command. Creating/Updating GitHub issue."
    ISSUE_TITLE="Errors while generating $CONTROLLER_NAME for ACK runtime $ACK_RUNTIME_VERSION"

    echo -n "auto-generate-controller.sh][INFO] Querying already open GitHub issue ... "
    ISSUE_NUMBER=$(gh issue list -R "$GH_ORG/$GH_ISSUE_REPO" -L 1 -s open --json number -S "$ISSUE_TITLE" --jq '.[0].number' -A @me )
    if [[ $? -ne 0 ]]; then
      echo ""
      echo "auto-generate-controller.sh][ERROR] unable to query open github issue. Skipping $CONTROLLER_NAME."
      continue
    fi
    echo "ok."

    MAKE_BUILD_OUTPUT=$(cat "$MAKE_BUILD_OUTPUT_FILE")
    MAKE_BUILD_ERROR_OUTPUT=$(cat "$MAKE_BUILD_ERROR_FILE")
    GH_ISSUE_BODY_TEMPLATE_FILE="$THIS_DIR/gh_issue_body_template.txt"
    GH_ISSUE_BODY_FILE=/tmp/"SERVICE_NAME"_gh_issue_body
    eval "echo \"$(cat "$GH_ISSUE_BODY_TEMPLATE_FILE")\"" > $GH_ISSUE_BODY_FILE

    if [[ -z $ISSUE_NUMBER ]]; then
      echo -n "auto-generate-controller.sh][INFO] No open issues exist. Creating a new GitHub issue inside $GH_ORG/$GH_ISSUE_REPO ... "
      if ! gh issue create -R "$GH_ORG/$GH_ISSUE_REPO" -t "$ISSUE_TITLE" -F "$GH_ISSUE_BODY_FILE" >/dev/null ; then
        echo ""
        echo "auto-generate-controller.sh][ERROR] Unable to create GitHub issue for reporting failure. Skipping $CONTROLLER_NAME."
        continue
      fi
      echo "ok"
      continue
    else
      echo -n "auto-generate-controller.sh][INFO] Updating error output in the body of existing issue#$ISSUE_NUMBER inside $GH_ORG/$GH_ISSUE_REPO ... "
      if ! gh issue edit "$ISSUE_NUMBER" -R "$GH_ORG/$GH_ISSUE_REPO" -F "$GH_ISSUE_BODY_FILE" >/dev/null; then
        echo ""
        echo "auto-generate-controller.sh][ERROR] Unable to edit GitHub issue$ISSUE_NUMBER with latest 'make build-controller' error. Skipping $CONTROLLER_NAME."
        continue
      fi
      echo "ok"
      continue
    fi
    # Skip creating PR for this service controller after updating GitHub issue.
    continue
  fi

  # print make build output in prowjob logs
  cat "$MAKE_BUILD_OUTPUT_FILE"
  pushd "$WORKSPACE_DIR/$CONTROLLER_NAME" >/dev/null
    echo -n "auto-generate-controller.sh][INFO] Updating 'go.mod' file in $CONTROLLER_NAME ... "
    if ! sed -i "s|aws-controllers-k8s/runtime $SERVICE_RUNTIME_VERSION|aws-controllers-k8s/runtime $ACK_RUNTIME_VERSION|" go.mod >/dev/null; then
      echo ""
      echo "auto-generate-controller.sh][ERROR] Unable to update go.mod file with latest runtime version. Skipping $CONTROLLER_NAME."
      continue
    fi
    echo "ok"

    echo -n "auto-generate-controller.sh][INFO] Executing 'go mod tidy' to cleanup redundant dependencies for $CONTROLLER_NAME ... "
    if ! go mod tidy >/dev/null; then
      echo ""
      echo "auto-generate-controller.sh][ERROR] Unable to execute 'go mod tidy'. Skipping $CONTROLLER_NAME."
      continue
    fi
    echo "ok"

    git add .
    COMMIT_MSG="ACK runtime update. $SERVICE_RUNTIME_VERSION => $ACK_RUNTIME_VERSION"
    echo -n "auto-generate-controller.sh][INFO] Adding commit with message: '$COMMIT_MSG' ... "
    if ! git commit -m "$COMMIT_MSG" >/dev/null; then
      echo ""
      echo "auto-generate-controller.sh][ERROR] Failed to add commit message for $CONTROLLER_NAME repository. Skipping $CONTROLLER_NAME."
      continue
    fi
    echo "ok"

    echo -n "auto-generate-controller.sh][INFO] Pushing changes to branch '$PR_SOURCE_GH_BRANCH' ... "
    if ! git push --force "https://$GITHUB_TOKEN@github.com/vijtrip2/$CONTROLLER_NAME.git" "$LOCAL_GIT_BRANCH:$PR_SOURCE_GH_BRANCH" >/dev/null 2>&1; then
      echo ""
      echo "auto-generate-controller.sh][ERROR] Failed to push the latest changes into remote repository. Skipping $CONTROLLER_NAME."
      continue
    fi
    echo "ok"

    echo -n "auto-generate-controller.sh][INFO] Finding existing open pull requests ... "
    PR_NUMBER=$(gh pr list -R "$GH_ORG/$CONTROLLER_NAME" -A @me -L 1 -s open --json number -S "$COMMIT_MSG" --jq '.[0].number')
    if [[ $? -ne 0 ]]; then
      echo ""
      echo "auto-generate-controller.sh][ERROR] Failed to query for an existing pull request for $GH_ORG/$CONTROLLER_NAME , from $PR_SOURCE_GH_BRANCH -> $PR_TARGET_GH_BRANCH branch."
    else
      echo "ok"
    fi

    MAKE_BUILD_OUTPUT=$(cat "$MAKE_BUILD_OUTPUT_FILE")
    GH_PR_BODY_TEMPLATE_FILE="$THIS_DIR/gh_pr_body_template.txt"
    GH_PR_BODY_FILE=/tmp/"SERVICE_NAME"_gh_pr_body
    eval "echo \"$(cat "$GH_PR_BODY_TEMPLATE_FILE")\"" > $GH_PR_BODY_FILE

    if [[ -z $PR_NUMBER ]]; then
      echo -n "auto-generate-controller.sh][INFO] No Existing PRs found. Creating a new pull request for $GH_ORG/$CONTROLLER_NAME , from $PR_SOURCE_GH_BRANCH -> $PR_TARGET_GH_BRANCH branch ... "
      if ! gh pr create -R "$GH_ORG/$CONTROLLER_NAME" -t "$COMMIT_MSG" -F "$GH_PR_BODY_FILE" -H "$PR_SOURCE_GH_BRANCH" -B "$PR_TARGET_GH_BRANCH" >/dev/null ; then
        echo ""
        echo "auto-generate-controller.sh][ERROR] Failed to create pull request. Skipping $CONTROLLER_NAME."
        continue
      fi
      echo "ok"
    else
      echo "auto-generate-controller.sh][INFO] PR#$PR_NUMBER already exists for $GH_ORG/$CONTROLLER_NAME , from $PR_SOURCE_GH_BRANCH -> $PR_TARGET_GH_BRANCH branch."
      echo -n "auto-generate-controller.sh][INFO] Updating PR body with latest 'make build-controller' output..."
      if ! gh pr edit "$PR_NUMBER" -R "$GH_ORG/$CONTROLLER_NAME" -F "$GH_PR_BODY_FILE" >/dev/null ; then
        echo ""
        echo "auto-generate-controller.sh][ERROR] Failed to update pull request."
        continue
      fi
      echo "ok"
    fi
    echo "auto-generate-controller.sh][INFO] Done. :) "
  popd >/dev/null
done

print_line_separation
