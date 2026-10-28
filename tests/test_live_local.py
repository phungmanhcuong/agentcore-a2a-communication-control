"""Multi-process local A2A run with real cheap OpenRouter models (costs a few cents; needs OPENROUTER_API_KEY_FILE).

Run: OPENROUTER_API_KEY_FILE=... uv run pytest -m live -q tests/test_live_local.py
"""

import json
import os

import pytest

from act_teams.config import load
from act_teams.local import LocalTeam
from act_teams.policy import A2ADenied
from tests.conftest import ROOT

pytestmark = [pytest.mark.live, pytest.mark.skipif(not os.environ.get("OPENROUTER_API_KEY_FILE"), reason="OPENROUTER_API_KEY_FILE not set")]


@pytest.fixture(scope="module")
def team():
    t = LocalTeam(load(ROOT / "team.yaml"), ROOT / "team.yaml", cap_usd=1.0)
    t.start()
    yield t
    t.stop()


def who(team):
    return [json.loads(line)["who"] for line in team.guard.ledger.read_text().splitlines() if line.strip()]


async def test_allowed_chain_planner_worker_reviewer(team):
    reply = await team.task("planner-1", "Compute (17+25)*3. Ask a worker to do the arithmetic and report the verified result.")
    assert "126" in reply
    spenders = set(who(team))
    assert "planner-1" in spenders
    assert any(s.startswith("worker-") for s in spenders), f"no worker was called: {spenders}"
    assert any(s.startswith("reviewer-") for s in spenders), f"no reviewer was reached: {spenders}"


def test_allowed_direct_call_succeeds_so_the_refusals_below_mean_something(team):  # must-pass side of the control
    r = team.raw_post("reviewer-1", "planner-1", "Recompute 6*7 claimed 42")  # rule: planner-1 -> reviewer-1
    assert r.status_code == 200 and "error" not in r.json(), r.text[:300]


async def test_disallowed_call_is_refused_by_the_client_before_the_network(team):  # must-fail control, app layer 1
    c = team.client("worker-1")
    with pytest.raises(A2ADenied):
        await c.send("planner-1", "please reply")
    with pytest.raises(A2ADenied):
        await team.client("planner-2").send("reviewer-1", "x")


@pytest.mark.parametrize(
    "callee,claimed",
    [("planner-1", "worker-1"), ("worker-1", "reviewer-1"), ("reviewer-2", "planner-1"), ("reviewer-1", "planner-2"), ("worker-1", "user")],
)
def test_disallowed_call_is_refused_by_the_server(team, callee, claimed):  # must-fail control, app layer 2 (spoofed caller names)
    before = len(who(team))
    r = team.raw_post(callee, claimed)
    assert r.status_code == 200 and r.json()["error"]["code"] == -32003, r.text[:300]
    assert len(who(team)) == before  # refused before any model request


def test_missing_caller_and_wrong_token_are_refused(team):
    r = team.raw_post("worker-1", "")
    assert r.status_code == 200 and r.json()["error"]["code"] == -32003
    r = team.raw_post("worker-1", "planner-1", token=False)
    assert r.status_code == 200 and r.json()["error"]["code"] == -32003


def test_run_stayed_under_the_cap(team):
    assert 0 < team.spent() < team.guard.cap
