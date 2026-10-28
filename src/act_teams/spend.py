"""Per-run spend guard. It reads the cost OpenRouter returns in `usage.cost` (JSON bodies and the last SSE chunk), adds it to a
ledger file shared by every process of the run, and refuses the next request once the cap is reached.

Overshoot is bounded: the check runs before each request, so at most the requests already in flight can pass the cap."""

from __future__ import annotations

import fcntl
import json
import os
import time
from collections.abc import AsyncIterator
from pathlib import Path

import httpx

DEFAULT_CAP_USD = 2.0


class SpendLimitExceeded(RuntimeError):
    """The run's spend cap is reached; no more model requests are sent."""


class SpendGuard:
    def __init__(self, ledger: str | Path, cap_usd: float = DEFAULT_CAP_USD):
        self.ledger = Path(ledger)
        self.cap = float(cap_usd)
        self.ledger.parent.mkdir(parents=True, exist_ok=True)
        self.ledger.touch(exist_ok=True)

    @classmethod
    def from_env(cls) -> SpendGuard:
        return cls(os.environ["ACT_SPEND_LEDGER"], float(os.environ.get("ACT_SPEND_CAP_USD", DEFAULT_CAP_USD)))

    def total(self) -> float:
        total = 0.0
        with self.ledger.open() as f:
            fcntl.flock(f, fcntl.LOCK_SH)
            for line in f:
                if line.strip():
                    total += float(json.loads(line)["usd"])
        return total

    def add(self, usd: float, who: str = "", model: str = "", tokens: dict | None = None) -> None:
        rec = {"t": round(time.time(), 3), "usd": float(usd), "who": who, "model": model, "tokens": tokens or {}}
        with self.ledger.open("a") as f:
            fcntl.flock(f, fcntl.LOCK_EX)
            f.write(json.dumps(rec) + "\n")

    def check(self) -> None:
        spent = self.total()
        if spent >= self.cap:
            raise SpendLimitExceeded(f"spend cap ${self.cap:.2f} reached (spent ${spent:.6f}); request refused")


def usage_from_json(obj: dict) -> dict | None:
    u = obj.get("usage")
    return u if isinstance(u, dict) and "cost" in u else None


class _TeeStream(httpx.AsyncByteStream):
    """Pass bytes through unchanged; parse complete lines for a usage object with a cost."""

    def __init__(self, inner: httpx.AsyncByteStream, on_usage, is_sse: bool):
        self.inner, self.on_usage, self.is_sse = inner, on_usage, is_sse
        self.buf = b""

    def _scan(self, final: bool) -> None:
        if self.is_sse:
            *lines, self.buf = self.buf.split(b"\n")
            for line in lines:
                if line.startswith(b"data: ") and b'"cost"' in line:
                    try:
                        u = usage_from_json(json.loads(line[6:]))
                    except ValueError:
                        continue
                    if u:
                        self.on_usage(u)
        elif final and b'"cost"' in self.buf:
            try:
                u = usage_from_json(json.loads(self.buf))
            except ValueError:
                return
            if u:
                self.on_usage(u)

    async def __aiter__(self) -> AsyncIterator[bytes]:
        async for chunk in self.inner:
            self.buf += chunk
            self._scan(False)
            yield chunk
        self._scan(True)

    async def aclose(self) -> None:
        await self.inner.aclose()


class SpendTransport(httpx.AsyncBaseTransport):
    """httpx transport that enforces the cap before each request and records the returned cost."""

    def __init__(self, guard: SpendGuard, who: str = "", inner: httpx.AsyncBaseTransport | None = None):
        self.guard, self.who = guard, who
        self.inner = inner or httpx.AsyncHTTPTransport()

    async def handle_async_request(self, request: httpx.Request) -> httpx.Response:
        self.guard.check()
        model = ""
        try:
            model = json.loads(request.content or b"{}").get("model", "")
        except ValueError:
            pass
        resp = await self.inner.handle_async_request(request)
        sse = "text/event-stream" in resp.headers.get("content-type", "")

        def record(u: dict) -> None:
            self.guard.add(float(u["cost"]), self.who, model, {k: u.get(k) for k in ("prompt_tokens", "completion_tokens")})

        resp.stream = _TeeStream(resp.stream, record, sse)  # type: ignore[assignment]
        return resp

    async def aclose(self) -> None:
        await self.inner.aclose()
