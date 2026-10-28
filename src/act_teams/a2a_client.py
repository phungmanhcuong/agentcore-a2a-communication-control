"""A2A client: JSON-RPC `message/send`, swappable auth, and the allow check in front of every call.

The allow check runs BEFORE any network use. Auth is an httpx.Auth object chosen by team.yaml a2a.auth:
  none   -> local runs
  sigv4  -> AgentCore with IAM (service bedrock-agentcore, credentials of the runtime's execution role)
  bearer -> AgentCore with a JWT authorizer (token from a callable)
"""

from __future__ import annotations

import json
import os
import uuid
from collections.abc import Callable, Generator
from typing import Any
from urllib.parse import quote

import httpx
from botocore.auth import SigV4Auth as _BotoSigV4
from botocore.awsrequest import AWSRequest
from botocore.credentials import Credentials

from .policy import A2ADenied, AllowPolicy

CALLER_HEADER = "X-Act-Caller"
TOKEN_HEADER = "X-Act-Token"  # infra/locals.tf request_headers must list both names (a runtime forwards only allow-listed headers)
SESSION_HEADER = "X-Amzn-Bedrock-AgentCore-Runtime-Session-Id"
SERVICE = "bedrock-agentcore"


class NoAuth(httpx.Auth):
    def auth_flow(self, request: httpx.Request) -> Generator[httpx.Request, httpx.Response]:
        yield request


class BearerAuth(httpx.Auth):
    def __init__(self, token: str | Callable[[], str]):
        self._token = token

    def auth_flow(self, request: httpx.Request) -> Generator[httpx.Request, httpx.Response]:
        token = self._token() if callable(self._token) else self._token
        request.headers["Authorization"] = f"Bearer {token}"
        yield request


class SigV4Auth(httpx.Auth):
    """AWS SigV4 for bedrock-agentcore. `credentials` is a botocore Credentials or a callable returning one (refreshing)."""

    requires_request_body = True

    def __init__(self, region: str, credentials: Credentials | Callable[[], Credentials] | None = None):
        self.region = region
        self._credentials = credentials

    def _creds(self) -> Credentials:
        c = self._credentials
        if c is None:
            import boto3

            c = boto3.Session().get_credentials()
            if c is None:
                raise RuntimeError("no AWS credentials for SigV4")
            return c.get_frozen_credentials()
        return c() if callable(c) else c

    def auth_flow(self, request: httpx.Request) -> Generator[httpx.Request, httpx.Response]:
        headers = {k: v for k, v in request.headers.items() if k.lower() != "connection"}
        aws = AWSRequest(method=request.method, url=str(request.url), data=request.content, headers=headers)
        _BotoSigV4(self._creds(), SERVICE, self.region).add_auth(aws)
        for k, v in aws.headers.items():
            request.headers[k] = v
        yield request


def make_auth(mode: str, region: str, **kw: Any) -> httpx.Auth:
    if mode == "none":
        return NoAuth()
    if mode == "sigv4":
        return SigV4Auth(region, kw.get("credentials"))
    if mode == "bearer":
        return BearerAuth(kw["token"])
    raise ValueError(f"unknown auth mode {mode!r}")


def runtime_url(arn: str, region: str) -> str:
    return f"https://{SERVICE}.{region}.amazonaws.com/runtimes/{quote(arn, safe='')}/invocations/"


def extract_text(result: dict) -> str:
    """Text of an A2A result, which is a Message or a Task."""
    texts: list[str] = []

    def parts(ps: list[dict] | None) -> None:
        for p in ps or []:
            if p.get("kind") == "text" or "text" in p:
                texts.append(p.get("text", ""))

    if result.get("kind") == "message":
        parts(result.get("parts"))
    else:
        for a in result.get("artifacts") or []:
            parts(a.get("parts"))
        if not texts:
            parts(((result.get("status") or {}).get("message") or {}).get("parts"))
    return "\n".join(t for t in texts if t)


class A2AError(RuntimeError):
    pass


class A2AClient:
    """directory maps peer name -> URL (local) ; the caller identity is sent as X-Act-Caller."""

    def __init__(
        self,
        caller: str,
        policy: AllowPolicy,
        directory: dict[str, str],
        auth: httpx.Auth,
        transport: httpx.AsyncBaseTransport | None = None,
        timeout: float = 300.0,
        run_token: str | None = None,
    ):
        self.caller, self.policy, self.directory, self.auth = caller, policy, directory, auth
        self.run_token = run_token  # AWS: read from Secrets Manager at start and passed in, so it is never put in os.environ
        self._transport, self._timeout = transport, timeout

    async def send(self, callee: str, text: str, session_id: str | None = None) -> str:
        self.policy.check(self.caller, callee)  # raises A2ADenied before any network use
        url = self.directory.get(callee)
        if url is None:
            raise A2AError(f"no address for peer {callee!r} in the peer directory")
        body = {
            "jsonrpc": "2.0",
            "id": uuid.uuid4().hex,
            "method": "message/send",
            "params": {"message": {"role": "user", "parts": [{"kind": "text", "text": text}], "messageId": uuid.uuid4().hex}},
        }
        headers = {CALLER_HEADER: self.caller, SESSION_HEADER: session_id or str(uuid.uuid4()), "Content-Type": "application/json"}
        run_token = self.run_token or os.environ.get("ACT_RUN_TOKEN")  # local runs set the env var: a per-run secret
        if run_token:
            headers[TOKEN_HEADER] = run_token
        async with httpx.AsyncClient(auth=self.auth, transport=self._transport, timeout=self._timeout) as c:
            r = await c.post(url, content=json.dumps(body), headers=headers)
        try:
            j = r.json()
        except ValueError:
            raise A2AError(f"{callee}: HTTP {r.status_code} with a non-JSON body") from None
        if r.status_code != 200 or "error" in j:
            raise A2AError(f"{callee}: HTTP {r.status_code} {json.dumps(j.get('error', j))[:300]}")
        return extract_text(j["result"])


def make_ask_peer_tool(client: A2AClient):
    """A Strands tool `ask_peer`, built only for the peers the policy allows this agent to call."""
    from strands import tool

    peers = client.policy.peers_of(client.caller)
    if not peers:
        return None

    @tool(name="ask_peer", description=f"Send a short message to another agent and return its reply. Allowed peers: {', '.join(peers)}.")
    async def ask_peer(peer: str, message: str) -> str:
        """Ask a peer agent.

        Args:
            peer: the peer's name, one of the allowed peers
            message: what to ask, one short paragraph
        """
        try:
            return await client.send(peer, message)
        except A2ADenied as e:
            return f"DENIED: {e}"
        except A2AError as e:
            return f"ERROR: {e}"

    return ask_peer
