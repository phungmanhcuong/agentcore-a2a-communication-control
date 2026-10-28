"""The run token: every peer call and every entry call carries X-Act-Token; AWS deployments cannot start without it."""

import httpx
import pytest
from fastapi.testclient import TestClient

from act_teams import a2a_client as ac
from act_teams import server
from act_teams.local import scrub_aws_env
from act_teams.policy import AllowPolicy

from .test_models_and_server import RPC, keyfile  # noqa: F401  (RPC passes the middleware and never calls a model; keyfile is a fixture)


class FakeSecrets:
    def __init__(self, value):
        self.value, self.asked = value, []

    def get_secret_value(self, SecretId):
        self.asked.append(SecretId)
        return {"SecretString": self.value}


def test_local_env_token_wins_and_needs_no_secret_store():
    assert server.resolve_run_token({"ACT_RUN_TOKEN": "tok-a", "ACT_RUN_TOKEN_SECRET_ID": "x"}, client=FakeSecrets("tok-b")) == "tok-a"


def test_token_is_read_from_the_secret_named_in_the_environment():
    c = FakeSecrets("tok-from-secret\n")
    assert server.resolve_run_token({"ACT_RUN_TOKEN_SECRET_ID": "act-teams/run-token"}, client=c) == "tok-from-secret"
    assert c.asked == ["act-teams/run-token"]


def test_empty_secret_is_an_error():  # must-fail: a blank token would switch the check off
    with pytest.raises(RuntimeError, match="empty"):
        server.resolve_run_token({"ACT_RUN_TOKEN_SECRET_ID": "s"}, client=FakeSecrets("  \n"))


def test_aws_deployment_refuses_to_start_without_a_token():  # must-fail: ACT_REQUIRE_RUN_TOKEN=true and nothing configured
    with pytest.raises(RuntimeError, match="ACT_REQUIRE_RUN_TOKEN"):
        server.resolve_run_token({"ACT_REQUIRE_RUN_TOKEN": "true"})


def test_without_the_requirement_a_missing_token_means_no_check_is_set_up():  # local default; AWS always sets the requirement
    assert server.resolve_run_token({}) is None


def test_local_scrub_removes_the_token_secret_settings():
    clean = scrub_aws_env({"ACT_RUN_TOKEN_SECRET_ID": "s", "ACT_REQUIRE_RUN_TOKEN": "true", "KEEP": "1"})
    assert "ACT_RUN_TOKEN_SECRET_ID" not in clean and "ACT_REQUIRE_RUN_TOKEN" not in clean and clean["KEEP"] == "1"


@pytest.fixture
def token_app(cfg, keyfile, tmp_path, monkeypatch):  # noqa: F811
    from act_teams.spend import SpendGuard

    monkeypatch.setenv("ACT_RUN_TOKEN", "tok-test")
    return server.create_app(cfg, "worker-1", {"reviewer-1": "http://r1/"}, ac.NoAuth(), guard=SpendGuard(tmp_path / "l.jsonl", 1.0))


def call(app, token):
    h = {ac.CALLER_HEADER: "planner-1"}  # the right caller name for worker-1
    if token:
        h[ac.TOKEN_HEADER] = token
    return TestClient(app).post("/", json=RPC, headers=h)


def test_right_caller_without_the_token_is_refused_with_200_and_32003(token_app):  # must-fail: a root caller that claims a team name
    r = call(token_app, None)
    assert r.status_code == 200 and r.json()["error"]["code"] == -32003 and "run token" in r.json()["error"]["message"]
    r = call(token_app, "wrong")
    assert r.status_code == 200 and r.json()["error"]["code"] == -32003


def test_right_caller_with_the_token_passes(token_app):  # must-pass: reaches the A2A handler (any code but -32003)
    r = call(token_app, "tok-test")
    assert r.status_code == 200 and r.json()["error"]["code"] != -32003


async def test_client_sends_the_token_when_it_is_set_and_not_otherwise(cfg, monkeypatch):
    seen = []

    def handler(request):
        seen.append(request.headers)
        return httpx.Response(
            200, json={"jsonrpc": "2.0", "id": "1", "result": {"kind": "message", "parts": [{"kind": "text", "text": "ok"}]}}
        )

    def client():
        return ac.A2AClient(
            "planner-1", AllowPolicy.from_config(cfg), {"worker-1": "http://w1/"}, ac.NoAuth(), httpx.MockTransport(handler)
        )

    monkeypatch.setenv("ACT_RUN_TOKEN", "tok-test")
    await client().send("worker-1", "x")
    monkeypatch.delenv("ACT_RUN_TOKEN")
    await client().send("worker-1", "x")
    assert seen[0][ac.TOKEN_HEADER] == "tok-test" and ac.TOKEN_HEADER not in seen[1]


def test_a_token_passed_in_works_with_nothing_in_the_environment(cfg, keyfile, tmp_path, monkeypatch):  # noqa: F811  # AWS path: memory only
    from act_teams.spend import SpendGuard

    monkeypatch.delenv("ACT_RUN_TOKEN", raising=False)
    app = server.create_app(
        cfg, "worker-1", {"reviewer-1": "http://r1/"}, ac.NoAuth(), guard=SpendGuard(tmp_path / "l.jsonl", 1.0), run_token="tok-mem"
    )
    assert call(app, None).json()["error"]["code"] == -32003
    assert call(app, "tok-mem").json()["error"]["code"] != -32003


async def test_client_sends_a_token_passed_in_without_the_environment(cfg, monkeypatch):
    monkeypatch.delenv("ACT_RUN_TOKEN", raising=False)
    seen = []

    def handler(request):
        seen.append(request.headers)
        return httpx.Response(
            200, json={"jsonrpc": "2.0", "id": "1", "result": {"kind": "message", "parts": [{"kind": "text", "text": "ok"}]}}
        )

    c = ac.A2AClient(
        "planner-1",
        AllowPolicy.from_config(cfg),
        {"worker-1": "http://w1/"},
        ac.NoAuth(),
        httpx.MockTransport(handler),
        run_token="tok-mem",
    )
    await c.send("worker-1", "x")
    assert seen[0][ac.TOKEN_HEADER] == "tok-mem"


def test_main_keeps_the_secret_token_out_of_the_environment(keyfile, tmp_path, monkeypatch):  # noqa: F811  # child processes of the agent must not inherit it
    import os

    captured = {}
    monkeypatch.delenv("ACT_RUN_TOKEN", raising=False)
    monkeypatch.setenv("ACT_AGENT_NAME", "worker-1")
    monkeypatch.setenv("ACT_SPEND_LEDGER", str(tmp_path / "ledger.jsonl"))
    monkeypatch.setenv("ACT_RUN_TOKEN_SECRET_ID", "act-teams/run-token")
    monkeypatch.setattr(server, "resolve_run_token", lambda *a, **k: "tok-secret")
    monkeypatch.setattr(server.uvicorn, "run", lambda app, **k: captured.update(app=app))
    server.main([])
    assert "ACT_RUN_TOKEN" not in os.environ and "tok-secret" not in os.environ.values()
    assert call(captured["app"], None).json()["error"]["code"] == -32003  # but the app enforces it
    assert call(captured["app"], "tok-secret").json()["error"]["code"] != -32003
