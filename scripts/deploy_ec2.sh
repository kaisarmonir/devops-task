#!/bin/bash
# Deploy an image to the EC2 host over SSM, smoke test it and roll back
# to the image that was running before if the smoke test fails.
#
# Usage: deploy_ec2.sh <image>
# Needs: INSTANCE_ID, APP_URL, AWS credentials and AWS_REGION
set -euo pipefail

image="${1:?usage: deploy_ec2.sh <image>}"
: "${INSTANCE_ID:?INSTANCE_ID is not set}"
: "${APP_URL:?APP_URL is not set}"

# run_remote <command>: run a shell command on the instance and fail if
# it failed. Remote stdout goes to stdout, everything else to stderr.
run_remote() {
  local id result
  id=$(aws ssm send-command \
    --instance-ids "$INSTANCE_ID" \
    --document-name AWS-RunShellScript \
    --parameters "$(jq -n --arg c "$1" '{commands: [$c]}')" \
    --query Command.CommandId --output text)

  # the waiter exits non-zero when the command fails, status is checked below
  aws ssm wait command-executed \
    --command-id "$id" --instance-id "$INSTANCE_ID" || true

  result=$(aws ssm get-command-invocation \
    --command-id "$id" --instance-id "$INSTANCE_ID" --output json)
  jq -r .StandardOutputContent <<<"$result"
  jq -r .StandardErrorContent <<<"$result" >&2
  echo "remote: $1 -> $(jq -r .Status <<<"$result")" >&2
  [ "$(jq -r .Status <<<"$result")" = "Success" ]
}

# smoke_test <tag>: /health answers and / reports the expected version
smoke_test() {
  curl -fsS --retry 10 --retry-delay 3 --retry-all-errors --max-time 5 \
    "$APP_URL/health" || return 1
  echo
  # set -e does not apply inside an "if" condition, so return explicitly
  local body
  body=$(curl -fsS --max-time 5 "$APP_URL/") || return 1
  echo "$body"
  grep -q "\"version\":\"$1\"" <<<"$body"
}

current=$(run_remote "cat /etc/app-image")
echo "currently running: $current"
echo "deploying: $image"

if run_remote "/usr/local/bin/run-app $image" && smoke_test "${image##*:}"; then
  echo "deploy succeeded: $image"
  exit 0
fi

echo "deploy failed, rolling back to $current" >&2
run_remote "/usr/local/bin/run-app $current"
smoke_test "${current##*:}"
echo "rolled back to $current" >&2
exit 1
