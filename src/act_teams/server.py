"""One agent = one A2A server (Strands A2AServer + FastAPI). Run locally with `python -m act_teams.server --agent worker-1 --port 9101`
or on AgentCore through main.py (port 9000, name from ACT_AGENT_NAME).

Callee-side allow check (app layer 2): every JSON-RPC POST must carry X-Act-Caller and (caller, me) must be allowed by team.yaml.
On AWS the caller's IAM identity is enforced by the resource policy and the caller's role policy; this check does not replace them."""

from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
from urllib.parse import urlparse

import uvicorn
from fastapi import FastAPI, Request
from fastapi.responses import JSONResponse
from strands import Agent

from . import a2a_client
from .config import AgentSpec, TeamConfig, load
from .models import build_model
from .policy import AllowPolicy
from .spend import SpendGuard
from .tools import calculator, word_count

TOKEN_HEADER = a2a_client.TOKEN_HEADER
# A refusal is a JSON-RPC error, which travels in the body with a 2xx status. AgentCore replaces any non-2xx answer from the container with
# HTTP 424 / -32055 "Runtime client error", so a 403 here never reached the caller (phase 2, 2026-10-10).
REFUSAL_STATUS = 200
OPEN_PATHS = ("/ping", "/.well-known/agent-card.json")


def load_peers(source: str, region: str) -> dict[str, str]:
    """name -> URL. A value that starts with 'arn:' is an AgentCore runtime ARN and becomes its invocation URL."""
    u = urlparse(source)
    if u.scheme in ("", "file"):
        raw = json.loads(Path(u.path or source).read_text())
    elif u.scheme == "s3":
        import boto3

        raw = json.loads(boto3.client("s3", region_name=region).get_object(Bucket=u.netloc, Key=u.path.lstrip("/"))["Body"].read())
    else:
        raise ValueError(f"unsupported peers source {source!r}")
    return {k: (a2a_client.runtime_url(v, region) if v.startswith("arn:") else v) for k, v in raw.items()}


def build_agent(
    cfg: TeamConfig,
    spec: AgentSpec,
    policy: AllowPolicy,
    directory: dict[str, str],
    auth,
    guard: SpendGuard | None = None,
    model=None,
    run_token: str | None = None,
) -> Agent:
    tools = []
    for t in spec.tools:
        if t == "calculator":
            tools.append(calculator)
        elif t == "word_count":
            tools.append(word_count)
        elif t == "ask_peer":
            allowed = {p: u for p, u in directory.items() if policy.allows(spec.name, p)}
            tool = a2a_client.make_ask_peer_tool(a2a_client.A2AClient(spec.name, policy, allowed, auth, run_token=run_token))
            if tool is not None:  # no allowed peers: the agent simply has no ask_peer tool
                tools.append(tool)
    model = model or build_model(spec.model, spec.name, guard)
    return Agent(
        model=model,
        name=spec.name,
        description=f"{spec.role} agent {spec.name}",
        system_prompt=spec.prompt,
        tools=tools,
        callback_handler=None,
    )


def create_app(
    cfg: TeamConfig,
    name: str,
    directory: dict[str, str],
    auth,
    public_url: str | None = None,
    guard: SpendGuard | None = None,
    model=None,
    host: str = "127.0.0.1",
    port: int = 9000,
    run_token: str | None = None,
) -> FastAPI:
    from strands.multiagent.a2a import A2AServer

    spec = cfg.agent(name)
    policy = AllowPolicy.from_config(cfg)
    server = A2AServer(
        agent_factory=lambda _ctx: build_agent(cfg, spec, policy, directory, auth, guard, model, run_token),
        host=host,
        port=port,
        http_url=public_url,
        serve_at_root=True,
    )
    app = server.to_fastapi_app()
    token = run_token or os.environ.get("ACT_RUN_TOKEN")

    @app.get("/ping")
    async def ping() -> dict:
        return {"status": "Healthy"}

    @app.middleware("http")
    async def allow_check(request: Request, call_next):
        if request.url.path in OPEN_PATHS and request.method == "GET":
            return await call_next(request)
        caller = request.headers.get(a2a_client.CALLER_HEADER, "")
        if token and request.headers.get(TOKEN_HEADER) != token:
            return JSONResponse(
                {"jsonrpc": "2.0", "id": None, "error": {"code": -32003, "message": "missing or wrong run token"}},
                status_code=REFUSAL_STATUS,
            )
        if not policy.allows(caller, name):
            return JSONResponse(
                {"jsonrpc": "2.0", "id": None, "error": {"code": -32003, "message": f"caller {caller!r} is not allowed to call {name!r}"}},
                status_code=REFUSAL_STATUS,
            )
        return await call_next(request)

    return app


def resolve_run_token(env=None, client=None) -> str | None:
    """The shared run token that every peer call and every entry call must carry in X-Act-Token.

    Local runs: ACT_RUN_TOKEN (set by LocalTeam). AWS: the value lives in the Secrets Manager secret named by ACT_RUN_TOKEN_SECRET_ID
    (Terraform generates it; it is never put in a runtime environment variable). With ACT_REQUIRE_RUN_TOKEN=true a missing token is an
    error, so a deployment cannot start with the token check silently off. The token proves team membership, not which agent is calling.
    """
    env = os.environ if env is None else env
    if env.get("ACT_RUN_TOKEN"):
        return env["ACT_RUN_TOKEN"]
    secret_id = env.get("ACT_RUN_TOKEN_SECRET_ID")
    if secret_id:
        if client is None:
            import boto3

            client = boto3.client("secretsmanager", region_name=env.get("AWS_REGION"))
        token = client.get_secret_value(SecretId=secret_id)["SecretString"].strip()
        if not token:
            raise RuntimeError(f"run token secret {secret_id!r} is empty")
        return token
    if env.get("ACT_REQUIRE_RUN_TOKEN") == "true":
        raise RuntimeError("ACT_REQUIRE_RUN_TOKEN=true but neither ACT_RUN_TOKEN nor ACT_RUN_TOKEN_SECRET_ID is set")
    return None


def find_config() -> str:
    """ACT_TEAM_CONFIG, else team.yaml in the working directory, next to the package (the zip root on AgentCore) or in the repo root."""
    here = Path(__file__).resolve()
    for c in (os.environ.get("ACT_TEAM_CONFIG"), Path.cwd() / "team.yaml", here.parents[1] / "team.yaml", here.parents[2] / "team.yaml"):
        if c and Path(c).is_file():
            return str(c)
    raise FileNotFoundError("team.yaml not found (set ACT_TEAM_CONFIG)")


def main(argv: list[str] | None = None) -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--agent", default=os.environ.get("ACT_AGENT_NAME"))
    ap.add_argument("--port", type=int, default=int(os.environ.get("ACT_PORT", 9000)))
    ap.add_argument("--host", default=os.environ.get("ACT_HOST", "127.0.0.1"))
    a = ap.parse_args(argv)
    # kept in memory and passed down; NOT copied into os.environ, so child processes of the agent do not inherit it
    token = resolve_run_token()
    cfg_path = find_config()
    cfg = load(cfg_path)
    auth_mode = os.environ.get("ACT_AUTH", cfg.auth)
    auth = a2a_client.make_auth(auth_mode, cfg.region)
    peers = load_peers(os.environ["ACT_PEERS_SOURCE"], cfg.region) if os.environ.get("ACT_PEERS_SOURCE") else {}
    public = os.environ.get("AGENTCORE_RUNTIME_URL")  # set by AgentCore; the card then advertises the invocation URL
    app = create_app(cfg, a.agent, peers, auth, public_url=public, guard=SpendGuard.from_env(), host=a.host, port=a.port, run_token=token)
    uvicorn.run(app, host=a.host, port=a.port, log_level="warning")


if __name__ == "__main__":
    main()
