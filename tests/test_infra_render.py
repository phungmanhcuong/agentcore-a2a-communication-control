"""Offline `terraform test` (mock_provider "aws", no AWS call) on the rendered AWS layers: resource-policy Allow and Deny, per-agent invoke policy,
base role, request-header allowlist. Skipped if terraform is not installed. Each mutation in scripts/mutants.sh (P1-P5, header) must make this fail."""

import os
import shutil
import subprocess

import pytest

from tests.conftest import ROOT

pytestmark = pytest.mark.skipif(shutil.which("terraform") is None, reason="terraform not installed")


def run_tf_test():
    return subprocess.run(["bash", str(ROOT / "scripts/tf_test.sh"), str(ROOT)], capture_output=True, text=True, env=os.environ)


def test_rendered_aws_layers_pass_the_terraform_test():
    r = run_tf_test()
    assert r.returncode == 0, f"terraform test rc={r.returncode}\n" + r.stdout[:6000] + r.stderr[-1000:]
    assert "Success! 5 passed, 0 failed." in r.stdout
