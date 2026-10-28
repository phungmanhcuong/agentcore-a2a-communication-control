import json

import httpx
import pytest
from fastapi.testclient import TestClient

from act_teams import models, server
from act_teams.a2a_client import CALLER_HEADER, NoAuth
from act_teams.spend import SpendGuard

SSE = (
    b'data: {"id":"g","choices":[{"index":0,"delta":{"role":"assistant","content":"pong"}}]}\n\n'
    b'data: {"id":"g","choices":[{"index":0,"delta":{},"finish_reason":"stop"}]}\n\n'
    b'data: {"id":"g","choices":[],"usage":{"prompt_tokens":5,"completion_tokens":2,"total_tokens":7,"cost":0.0007}}\n\ndata: [DONE]\n\n'
)


@pytest.fixture
def keyfile(tmp_path, monkeypatch):
    p = tmp_path / "k"
    p.write_text("sk-test-not-a-real-key\n")
    monkeypatch.setenv("OPENROUTER_API_KEY_FILE", str(p))
    return p


async def test_every_request_denies_data_collection_and_cost_is_read(cfg, keyfile, tmp_path):
    bodies = []

    def handler(req: httpx.Request) -> httpx.Response:
        bodies.append(json.loads(req.content))
        assert req.headers["authorization"] == "Bearer sk-test-not-a-real-key"
        assert str(req.url).startswith("https://openrouter.ai/api/v1/")
        return httpx.Response(200, stream=httpx.ByteStream(SSE), headers={"content-type": "text/event-stream"})

    guard = SpendGuard(tmp_path / "l.jsonl", 1.0)
    m = models.build_model(cfg.agent("worker-1").model, "worker-1", guard, httpx.MockTransport(handler))
    async for _ in m.stream([{"role": "user", "content": [{"text": "ping"}]}]):
        pass
    b = bodies[0]
    assert b["provider"] == {"data_collection": "deny"}  # production request contract
    assert b["usage"] == {"include": True}
    assert b["model"] == "openai/gpt-oss-20b" and b["max_tokens"] == 2000
    assert guard.total() == pytest.approx(0.0007)


def test_key_comes_from_the_file_only(monkeypatch):  # must-fail: no env var, no key
    monkeypatch.delenv("OPENROUTER_API_KEY_FILE", raising=False)
    monkeypatch.delenv("ACT_OPENROUTER_SECRET_ID", raising=False)
    with pytest.raises(KeyError):
        models.read_key()


def test_secret_id_set_locally_fails_without_any_network_call(monkeypatch):  # must-fail control for "a local run cannot reach AWS"
    import socket

    from botocore.exceptions import BotoCoreError

    attempts = []

    def no_network(*a, **k):
        attempts.append(a)
        raise AssertionError("a socket was opened")

    monkeypatch.delenv("OPENROUTER_API_KEY_FILE", raising=False)
    monkeypatch.setenv("ACT_OPENROUTER_SECRET_ID", "act-teams/openrouter")
    monkeypatch.setenv("AWS_REGION", "us-east-1")
    monkeypatch.setattr(socket, "create_connection", no_network)
    monkeypatch.setattr(socket.socket, "connect", no_network)
    with pytest.raises(BotoCoreError) as e:  # NoCredentialsError: the credential chain found nothing and IMDS is off
        models.read_key()
    assert type(e.value).__name__ == "NoCredentialsError"
    assert attempts == []


def test_conftest_scrub_removes_credentials_and_the_secret_id(monkeypatch):
    from act_teams.local import scrub_aws_env

    dirty = {
        "AWS_PROFILE": "p",
        "AWS_ACCESS_KEY_ID": "x",
        "AWS_SESSION_TOKEN": "x",
        "ACT_OPENROUTER_SECRET_ID": "s",
        "AWS_CONTAINER_CREDENTIALS_FULL_URI": "u",
        "KEEP": "1",
    }
    clean = scrub_aws_env(dirty)
    assert clean["KEEP"] == "1" and clean["AWS_EC2_METADATA_DISABLED"] == "true"
    assert not [k for k in clean if k in dirty and k != "KEEP"]


@pytest.fixture
def app(cfg, keyfile, tmp_path, monkeypatch):
    monkeypatch.setenv("ACT_RUN_TOKEN", "tok")
    guard = SpendGuard(tmp_path / "l.jsonl", 1.0)
    return server.create_app(cfg, "worker-1", {"reviewer-1": "http://r1/"}, NoAuth(), guard=guard)


RPC = {"jsonrpc": "2.0", "id": "1", "method": "tasks/get", "params": {"id": "does-not-exist"}}  # passes the middleware, never calls a model


def post(client, caller=None, token="tok"):
    h = {}
    if caller:
        h[CALLER_HEADER] = caller
    if token:
        h["X-Act-Token"] = token
    return client.post("/", json=RPC, headers=h)


def test_open_paths_need_no_caller(app):
    c = TestClient(app)
    assert c.get("/ping").json() == {"status": "Healthy"}
    card = c.get("/.well-known/agent-card.json").json()
    assert card["name"] == "worker-1"


def test_allowed_caller_passes_the_middleware(app):
    r = post(TestClient(app), "planner-1")
    assert r.status_code == 200 and "error" in r.json() and r.json()["error"]["code"] != -32003  # reached the A2A handler


@pytest.mark.parametrize("caller", ["reviewer-1", "worker-2", "planner-1x", "user", "", None])
def test_disallowed_or_missing_caller_is_refused_in_a_200_body(
    app, caller
):  # must-fail controls, including a spoof of a name that is not allowed
    r = post(TestClient(app), caller)
    assert r.status_code == 200 and r.json()["error"]["code"] == -32003  # 2xx: AgentCore turns any non-2xx into 424 / -32055


def test_wrong_or_missing_run_token_is_refused_in_a_200_body(app):  # must-fail
    for tok in ("nope", None):
        r = post(TestClient(app), "planner-1", token=tok)
        assert r.status_code == 200 and r.json()["error"]["code"] == -32003 and "run token" in r.json()["error"]["message"]


def test_peers_file_with_arns_becomes_invocation_urls(tmp_path):
    f = tmp_path / "p.json"
    f.write_text(
        json.dumps({"a": "http://127.0.0.1:1/", "b": "arn:aws:bedrock-agentcore:us-east-1:123456789012:runtime/act_teams_b-XyZ0123456"})
    )
    d = server.load_peers(str(f), "us-east-1")
    assert d["a"] == "http://127.0.0.1:1/"
    assert d["b"].startswith("https://bedrock-agentcore.us-east-1.amazonaws.com/runtimes/arn%3Aaws")


def test_agent_without_allowed_peers_gets_no_ask_peer_tool(cfg, keyfile, tmp_path):
    guard = SpendGuard(tmp_path / "l.jsonl", 1.0)
    from act_teams.policy import AllowPolicy

    p = AllowPolicy.from_config(cfg)
    rev = server.build_agent(cfg, cfg.agent("reviewer-1"), p, {"worker-1": "http://w/"}, NoAuth(), guard)
    assert sorted(rev.tool_names) == ["calculator"]
    wk = server.build_agent(cfg, cfg.agent("worker-1"), p, {"reviewer-1": "http://r/", "planner-1": "http://p/"}, NoAuth(), guard)
    assert "ask_peer" in wk.tool_names


def test_key_from_secrets_manager_when_no_file(monkeypatch):
    class FakeSM:
        def get_secret_value(self, SecretId):
            assert SecretId == "act-teams/openrouter"
            return {"SecretString": "sk-from-secret\n"}

    monkeypatch.delenv("OPENROUTER_API_KEY_FILE", raising=False)
    monkeypatch.setenv("ACT_OPENROUTER_SECRET_ID", "act-teams/openrouter")
    monkeypatch.setattr("boto3.client", lambda service, **kw: FakeSM() if service == "secretsmanager" else None)
    assert models.read_key() == "sk-from-secret"


def test_find_config_finds_the_repo_file_and_refuses_when_absent(monkeypatch, tmp_path):
    monkeypatch.delenv("ACT_TEAM_CONFIG", raising=False)
    assert server.find_config().endswith("team.yaml")
    monkeypatch.setenv("ACT_TEAM_CONFIG", str(tmp_path / "nope.yaml"))
    assert server.find_config().endswith("team.yaml")  # a missing override falls through to the next candidate, it is not used blindly
