import json

import httpx
import pytest

from act_teams.spend import SpendGuard, SpendLimitExceeded, SpendTransport

JSON_BODY = {"id": "x", "choices": [], "usage": {"prompt_tokens": 10, "completion_tokens": 5, "cost": 0.0123}}
SSE = (
    b'data: {"choices":[{"delta":{"content":"hi"}}]}\n\n'
    b'data: {"choices":[],"usage":{"prompt_tokens":7,"completion_tokens":3,"cost":0.0042}}\n\ndata: [DONE]\n\n'
)


def transport(guard, body, ctype):
    inner = httpx.MockTransport(lambda req: httpx.Response(200, stream=httpx.ByteStream(body), headers={"content-type": ctype}))
    return SpendTransport(guard, "w", inner)


async def post(t):
    async with httpx.AsyncClient(transport=t) as c:
        return await c.post("https://x/y", json={"model": "m"})


async def test_json_cost_is_recorded(tmp_path):
    g = SpendGuard(tmp_path / "l.jsonl", 1.0)
    r = await post(transport(g, json.dumps(JSON_BODY).encode(), "application/json"))
    assert r.json()["usage"]["cost"] == 0.0123  # body passes through unchanged
    assert g.total() == pytest.approx(0.0123)


async def test_sse_cost_is_recorded(tmp_path):
    g = SpendGuard(tmp_path / "l.jsonl", 1.0)
    r = await post(transport(g, SSE, "text/event-stream"))
    assert r.content == SSE
    assert g.total() == pytest.approx(0.0042)


async def test_cap_stops_the_next_request(tmp_path):  # must-fail control
    g = SpendGuard(tmp_path / "l.jsonl", 0.01)
    t = transport(g, json.dumps(JSON_BODY).encode(), "application/json")
    await post(t)  # costs 0.0123 > cap
    with pytest.raises(SpendLimitExceeded):
        await post(t)


async def test_response_without_cost_adds_nothing(tmp_path):
    g = SpendGuard(tmp_path / "l.jsonl", 1.0)
    await post(transport(g, b'{"usage": {"prompt_tokens": 1}}', "application/json"))
    assert g.total() == 0.0


def test_ledger_is_shared_between_guards(tmp_path):
    a, b = SpendGuard(tmp_path / "l.jsonl", 1.0), SpendGuard(tmp_path / "l.jsonl", 1.0)
    a.add(0.25)
    b.add(0.5)
    assert a.total() == b.total() == pytest.approx(0.75)
