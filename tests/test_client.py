import socket

import httpx
import pytest
from botocore.credentials import Credentials

from act_teams import a2a_client as ac
from act_teams.policy import A2ADenied, AllowPolicy


def ok_transport(seen):
    def handler(req: httpx.Request) -> httpx.Response:
        seen.append(req)
        return httpx.Response(
            200,
            json={
                "jsonrpc": "2.0",
                "id": "1",
                "result": {"kind": "message", "role": "agent", "messageId": "m", "parts": [{"kind": "text", "text": "pong"}]},
            },
        )

    return httpx.MockTransport(handler)


async def test_allowed_call_sends_caller_and_session_headers(cfg):
    seen = []
    c = ac.A2AClient("planner-1", AllowPolicy.from_config(cfg), {"worker-1": "http://w1/"}, ac.NoAuth(), ok_transport(seen))
    assert await c.send("worker-1", "ping") == "pong"
    h = seen[0].headers
    assert h[ac.CALLER_HEADER] == "planner-1"
    assert len(h[ac.SESSION_HEADER]) >= 33  # AgentCore wants a session id of at least 33 characters
    assert b'"message/send"' in seen[0].content


async def test_disallowed_call_raises_before_any_socket_is_used(cfg, monkeypatch):  # must-fail control
    def no_network(*a, **k):
        raise AssertionError("a socket was opened for a disallowed call")

    monkeypatch.setattr(socket.socket, "connect", no_network)
    monkeypatch.setattr(socket, "getaddrinfo", no_network)
    c = ac.A2AClient("worker-1", AllowPolicy.from_config(cfg), {"planner-1": "http://127.0.0.1:1/"}, ac.NoAuth())
    with pytest.raises(A2ADenied):
        await c.send("planner-1", "hello")


async def test_unknown_peer_is_refused(cfg):
    c = ac.A2AClient("planner-1", AllowPolicy.from_config(cfg), {}, ac.NoAuth(), ok_transport([]))
    with pytest.raises(ac.A2AError):
        await c.send("worker-1", "x")  # allowed by policy but no address in the directory


async def test_http_error_becomes_a2a_error(cfg):
    t = httpx.MockTransport(lambda r: httpx.Response(403, json={"jsonrpc": "2.0", "id": None, "error": {"code": -32003, "message": "no"}}))
    c = ac.A2AClient("planner-1", AllowPolicy.from_config(cfg), {"worker-1": "http://w1/"}, ac.NoAuth(), t)
    with pytest.raises(ac.A2AError, match="403"):
        await c.send("worker-1", "x")


async def test_200_with_error_body_becomes_a2a_error(cfg):  # how the server refuses now: HTTP 200 plus a JSON-RPC error
    t = httpx.MockTransport(lambda r: httpx.Response(200, json={"jsonrpc": "2.0", "id": None, "error": {"code": -32003, "message": "no"}}))
    c = ac.A2AClient("planner-1", AllowPolicy.from_config(cfg), {"worker-1": "http://w1/"}, ac.NoAuth(), t)
    with pytest.raises(ac.A2AError, match="-32003"):
        await c.send("worker-1", "x")


def test_ask_peer_tool_exists_only_for_agents_with_allowed_peers(cfg):
    p = AllowPolicy.from_config(cfg)
    assert ac.make_ask_peer_tool(ac.A2AClient("planner-1", p, {}, ac.NoAuth())) is not None
    assert ac.make_ask_peer_tool(ac.A2AClient("reviewer-1", p, {}, ac.NoAuth())) is None  # must-fail: no peers, no tool
    spec = ac.make_ask_peer_tool(ac.A2AClient("planner-2", p, {}, ac.NoAuth())).tool_spec
    assert "worker-1" in spec["description"] and "reviewer" not in spec["description"]


async def test_ask_peer_tool_reports_denial_as_text(cfg):
    p = AllowPolicy.from_config(cfg)
    tool = ac.make_ask_peer_tool(ac.A2AClient("planner-1", p, {"worker-1": "http://w1/"}, ac.NoAuth(), ok_transport([])))
    out = await tool(peer="planner-2", message="hi")
    assert out.startswith("DENIED")


def test_sigv4_signature_shape():
    auth = ac.SigV4Auth("us-east-1", Credentials("AKIDEXAMPLE", "secretexample", "tok"))
    req = httpx.Request("POST", "https://bedrock-agentcore.us-east-1.amazonaws.com/runtimes/arn%3Aaws/invocations/", content=b"{}")
    next(auth.sync_auth_flow(req))
    a = req.headers["authorization"]
    assert a.startswith("AWS4-HMAC-SHA256 Credential=AKIDEXAMPLE/") and "/us-east-1/bedrock-agentcore/aws4_request" in a
    assert "x-amz-date" in req.headers and req.headers["x-amz-security-token"] == "tok"


def test_sigv4_signature_changes_with_the_body():  # must-fail: the body is part of the signature
    auth = ac.SigV4Auth("us-east-1", Credentials("AKIDEXAMPLE", "secretexample"))
    sigs = []
    for body in (b"{}", b'{"a":1}'):
        r = httpx.Request(
            "POST", "https://bedrock-agentcore.us-east-1.amazonaws.com/x", content=body, headers={"x-amz-date": "20261010T000000Z"}
        )
        next(auth.sync_auth_flow(r))
        sigs.append(r.headers["authorization"].split("Signature=")[1])
    assert sigs[0] != sigs[1]


def test_bearer_and_none_auth_and_factory():
    r = httpx.Request("GET", "https://x/")
    next(ac.make_auth("bearer", "us-east-1", token=lambda: "t0k").sync_auth_flow(r))
    assert r.headers["authorization"] == "Bearer t0k"
    r2 = httpx.Request("GET", "https://x/")
    next(ac.make_auth("none", "us-east-1").sync_auth_flow(r2))
    assert "authorization" not in r2.headers
    with pytest.raises(ValueError):
        ac.make_auth("kerberos", "us-east-1")


def test_runtime_url_escapes_the_arn():
    u = ac.runtime_url("arn:aws:bedrock-agentcore:us-east-1:123456789012:runtime/act_teams_worker_1-AbCdEfGhIj", "us-east-1")
    assert u == (
        "https://bedrock-agentcore.us-east-1.amazonaws.com/runtimes/"
        "arn%3Aaws%3Abedrock-agentcore%3Aus-east-1%3A123456789012%3Aruntime%2Fact_teams_worker_1-AbCdEfGhIj/invocations/"
    )


def test_extract_text_from_task_and_message():
    assert (
        ac.extract_text(
            {"kind": "task", "artifacts": [{"parts": [{"kind": "text", "text": "a"}]}, {"parts": [{"kind": "text", "text": "b"}]}]}
        )
        == "a\nb"
    )
    assert ac.extract_text({"kind": "task", "status": {"message": {"parts": [{"kind": "text", "text": "s"}]}}}) == "s"
