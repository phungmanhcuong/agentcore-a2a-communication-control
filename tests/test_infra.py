"""Terraform and Python must expand team.yaml identically. Terraform side: `terraform console` on a scratch copy with a local throw-away state
(offline: no AWS call). Skipped if terraform is not installed."""

import shutil
import subprocess
import sys

import pytest
import yaml

from act_teams.a2a_client import CALLER_HEADER, TOKEN_HEADER
from act_teams.config import load
from act_teams.policy import USER, AllowPolicy
from tests.conftest import ROOT

pytestmark = pytest.mark.skipif(shutil.which("terraform") is None, reason="terraform not installed")
sys.path.insert(0, str(ROOT / "scripts"))


def tf(path):
    from tf_expansion import evaluate

    return evaluate(path)


def python_side(path):
    cfg = load(path)
    p = AllowPolicy.from_config(cfg)
    pairs = sorted((a, b) for a, b in p.pairs if a != USER)
    return (
        pairs,
        {a: list(p.peers_of(a)) for a in cfg.agents},
        {a: list(p.callers_of(a)) for a in cfg.agents if True},
        sorted(p.peers_of(USER)),
    )


def check_parity(path):
    t = tf(path)
    pairs, peers, callers, entry = python_side(path)
    assert sorted((x["from"], x["to"]) for x in t["pairs"]) == pairs
    assert t["peers"] == peers
    assert {a: [c for c in cs if c != USER] for a, cs in callers.items()} == t["callers"]
    assert sorted(t["entry"]) == entry
    assert t["runtime_name"]["worker-1"] == "act_teams_worker_1"  # underscores: runtime names allow no hyphen
    return t


def test_parity_for_team_yaml():
    check_parity(ROOT / "team.yaml")


def test_parity_for_the_3x10_scale_config(tmp_path):
    out = tmp_path / "scale.yaml"
    subprocess.run([sys.executable, str(ROOT / "scripts/make_scale_config.py"), str(out), "10"], check=True, capture_output=True)
    t = check_parity(out)
    assert len(t["runtime_name"]) == 30 and len(t["pairs"]) == 10 * 10 + 10 * 10 + 1


def test_terraform_follows_the_config_and_is_not_static(tmp_path, raw):  # must-fail control: a changed rule changes both sides
    raw["a2a"]["allow"].append({"from": "reviewer-2", "to": "worker-3"})
    f = tmp_path / "team.yaml"
    f.write_text(yaml.safe_dump(raw))
    t = check_parity(f)
    assert {"from": "reviewer-2", "to": "worker-3"} in t["pairs"]


def test_terraform_rejects_a_rule_for_an_unknown_role(tmp_path, raw):  # must-fail control
    raw["a2a"]["allow"].append({"from": "role:ghost", "to": "role:worker"})
    f = tmp_path / "team.yaml"
    f.write_text(yaml.safe_dump(raw))
    with pytest.raises(subprocess.CalledProcessError):
        tf(f)


def test_terraform_forwards_exactly_the_headers_the_app_reads():  # a runtime forwards only allow-listed headers; names compare case-insensitively
    t = tf(ROOT / "team.yaml")
    assert sorted(h.lower() for h in t["request_headers"]) == sorted([CALLER_HEADER.lower(), TOKEN_HEADER.lower()])
    assert not any(h.lower().startswith(("x-amz-", "x-amzn-")) for h in t["request_headers"])  # AWS restricts these prefixes
