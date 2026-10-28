#!/usr/bin/env bash
# Offline `terraform test` (mock_provider "aws": no credentials, no AWS call) on a scratch copy, so no .terraform or state lands in the repo.
# Usage: scripts/tf_test.sh [repo-root]   (the mutation check runs it on a mutated copy)
set -uo pipefail
ROOT=$(cd "${1:-$(dirname "$0")/..}" && pwd)
TMP=$(mktemp -d "${TMPDIR:-/tmp}/tftest.XXXXXX"); trap 'rm -rf "$TMP"' EXIT
mkdir "$TMP/w"; cp -r "$ROOT/infra" "$TMP/w/infra"; cp "$ROOT/team.yaml" "$TMP/w/"; rm -rf "$TMP/w/infra/.terraform"
cd "$TMP/w/infra" || exit 2
export TF_IN_AUTOMATION=1 AWS_EC2_METADATA_DISABLED=true
unset AWS_PROFILE AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN
terraform init -backend=false -input=false -no-color >/dev/null 2>&1 || { echo "terraform init failed"; exit 2; }
terraform test -var code_zip_path=tests/fixture.zip -no-color
