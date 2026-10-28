import re
import shutil
import subprocess
import sys

import pytest

from tests.conftest import ROOT

sys.path.insert(0, str(ROOT / "scripts"))
import check_iam_scope
import count_resources


def test_resource_count_by_type():
    out = count_resources.count(ROOT / "team.yaml", ROOT / "infra")
    r = out["resources_by_type"]
    assert out["agents"] == 9
    assert (
        r["aws_bedrockagentcore_agent_runtime"]
        == r["aws_iam_role"]
        == r["aws_bedrockagentcore_resource_policy"]
        == r["aws_cloudwatch_log_group"]
        == 9
    )
    assert (
        r["aws_iam_role_policy"] == 9 + 6
    )  # 9 base + one invoke policy for each of the 6 agents that has allowed peers (reviewers have none)
    assert r["aws_s3_object"] == 1 + 9 and r["aws_secretsmanager_secret"] == 2
    assert r["random_password"] == r["aws_secretsmanager_secret_version"] == 1  # the run token
    assert out["resources_total"] == sum(r.values()) == 70


def test_counter_stops_on_an_expression_it_does_not_understand(tmp_path):  # must-fail control
    (tmp_path / "x.tf").write_text('resource "aws_s3_bucket" "b" {\n  for_each = toset(["a"])\n}\n')
    with pytest.raises(SystemExit):
        count_resources.count(ROOT / "team.yaml", tmp_path)


def test_no_wildcard_iam_in_the_real_code():
    assert check_iam_scope.violations(ROOT / "infra") == []


@pytest.mark.parametrize(
    "planted",
    [
        'data "aws_iam_policy_document" "x" {\n  statement {\n    actions   = ["bedrock-agentcore:InvokeAgentRuntime"]\n    resources = ["*"]\n  }\n}\n',
        'data "aws_iam_policy_document" "x" {\n  statement {\n    actions   = ["bedrock-agentcore:*"]\n    resources = ["arn:aws:x"]\n  }\n}\n',
        'data "aws_iam_policy_document" "x" {\n  statement {\n    actions   = ["s3:Get*"]\n    resources = ["arn:aws:x"]\n  }\n}\n',
    ],
)
def test_guard_flags_planted_wildcards(tmp_path, planted):  # must-fail control
    (tmp_path / "bad.tf").write_text(planted)
    assert check_iam_scope.violations(tmp_path)


@pytest.mark.skipif(shutil.which("checkov") is None, reason="checkov not installed")
def test_checkov_flags_a_planted_open_bucket_and_admin_role(tmp_path):  # must-fail control for the security scan
    shutil.copytree(ROOT / "infra", tmp_path / "infra", ignore=shutil.ignore_patterns(".terraform"))
    with open(tmp_path / "infra" / "planted.tf", "w") as f:
        f.write(
            'resource "aws_s3_bucket_public_access_block" "bad" {\n  bucket = "x"\n  block_public_acls = false\n  block_public_policy = false\n}\n'
            'resource "aws_iam_policy" "admin" {\n  name = "x"\n  policy = jsonencode({Version = "2012-10-17", Statement = [{Effect = "Allow", Action = "*", Resource = "*"}]})\n}\n'
        )
    r = subprocess.run(
        ["checkov", "-d", str(tmp_path / "infra"), "--framework", "terraform", "--quiet", "--compact"], capture_output=True, text=True
    )
    assert r.returncode != 0 and "planted.tf" in r.stdout
    clean = subprocess.run(
        ["checkov", "-d", str(ROOT / "infra"), "--framework", "terraform", "--quiet", "--compact"], capture_output=True, text=True
    )
    assert clean.returncode == 0, clean.stdout[-500:]


def depends_on_of(tf_text: str, rtype: str, name: str) -> list[str]:
    for kind, t, n, body in count_resources.blocks(tf_text):
        if kind == "resource" and (t, n) == (rtype, name):
            m = re.search(r"^\s{2}depends_on\s*=\s*\[(.*?)\]", body, re.MULTILINE | re.DOTALL)
            return [x.strip() for x in m.group(1).split(",") if x.strip()] if m else []
    raise AssertionError(f"{rtype}.{name} not found")


RUNTIME = ("aws_bedrockagentcore_agent_runtime", "agent")


def test_runtimes_wait_for_the_run_token_value():  # a container reads the secret VALUE at start; it must exist first
    deps = depends_on_of((ROOT / "infra/runtimes.tf").read_text(), *RUNTIME)
    assert "aws_secretsmanager_secret_version.run_token" in deps and "aws_iam_role_policy.base" in deps


def test_the_dependency_check_fails_when_the_version_is_missing():  # must-fail control on the planted text
    planted = 'resource "aws_bedrockagentcore_agent_runtime" "agent" {\n  depends_on = [aws_iam_role_policy.base]\n}\n'
    assert "aws_secretsmanager_secret_version.run_token" not in depends_on_of(planted, *RUNTIME)
    assert depends_on_of('resource "aws_bedrockagentcore_agent_runtime" "agent" {\n}\n', *RUNTIME) == []
