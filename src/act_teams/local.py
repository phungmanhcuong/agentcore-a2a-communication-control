"""Run a team on this host: one OS process per agent, each an A2A server on 127.0.0.1, real OpenRouter models.

  uv run python -m act_teams.local run --task "..." [--entry planner-1] [--cap 2.0] [--agents planner-1,worker-1,reviewer-1]
The run directory (logs, peers.json, spend ledger) is outside the repository; the key file is read through OPENROUTER_API_KEY_FILE."""

from __future__ import annotations

import argparse
import asyncio
import json
import os
import secrets
import socket
import subprocess
import sys
import time
import uuid
from pathlib import Path

import httpx

from .a2a_client import CALLER_HEADER, TOKEN_HEADER, A2AClient, NoAuth
from .config import TeamConfig, load
from .policy import USER, AllowPolicy
from .spend import SpendGuard

# A local run must never reach AWS: the key comes from OPENROUTER_API_KEY_FILE, and nothing may fall back to Secrets Manager or the instance role.
AWS_ENV_PREFIXES = (
    "AWS_ACCESS_KEY",
    "AWS_SECRET",
    "AWS_SESSION",
    "AWS_PROFILE",
    "AWS_DEFAULT_PROFILE",
    "AWS_CONTAINER",
    "AWS_WEB_IDENTITY",
    "AWS_ROLE",
)
AWS_ENV_EXACT = (
    "ACT_OPENROUTER_SECRET_ID",
    "ACT_RUN_TOKEN_SECRET_ID",
    "ACT_REQUIRE_RUN_TOKEN",
    "AWS_SHARED_CREDENTIALS_FILE",
    "AWS_CONFIG_FILE",
)


def scrub_aws_env(env: dict[str, str]) -> dict[str, str]:
    """env without anything that lets boto3 find credentials, plus the switches that stop it from asking the instance metadata service."""
    out = {k: v for k, v in env.items() if k not in AWS_ENV_EXACT and not k.startswith(AWS_ENV_PREFIXES)}
    out.update(
        AWS_EC2_METADATA_DISABLED="true",
        AWS_SHARED_CREDENTIALS_FILE="/nonexistent/aws-credentials",
        AWS_CONFIG_FILE="/nonexistent/aws-config",
    )
    return out


DEFAULT_RUNS = Path(os.environ.get("ACT_RUNS_DIR", "/tmp/act-teams/runs"))


def free_ports(n: int) -> list[int]:
    socks, ports = [], []
    for _ in range(n):
        s = socket.socket()
        s.bind(("127.0.0.1", 0))
        socks.append(s)
        ports.append(s.getsockname()[1])
    for s in socks:
        s.close()
    return ports


class LocalTeam:
    def __init__(
        self, cfg: TeamConfig, config_path: str | Path, agents: list[str] | None = None, run_dir: Path | None = None, cap_usd: float = 2.0
    ):
        self.cfg, self.config_path = cfg, Path(config_path).resolve()
        self.names = agents or list(cfg.agents)
        self.run_dir = run_dir or DEFAULT_RUNS / time.strftime("%Y%m%dT%H%M%S")
        self.run_dir.mkdir(parents=True, exist_ok=True)
        self.guard = SpendGuard(self.run_dir / "spend.jsonl", cap_usd)
        self.token = secrets.token_hex(16)
        self.urls: dict[str, str] = {}
        self.procs: dict[str, subprocess.Popen] = {}
        self.policy = AllowPolicy.from_config(cfg)

    def start(self, timeout: float = 90.0) -> None:
        ports = free_ports(len(self.names))
        self.urls = {n: f"http://127.0.0.1:{p}/" for n, p in zip(self.names, ports, strict=True)}
        peers = self.run_dir / "peers.json"
        peers.write_text(json.dumps(self.urls))
        env = {
            **scrub_aws_env(dict(os.environ)),
            "ACT_TEAM_CONFIG": str(self.config_path),
            "ACT_PEERS_SOURCE": str(peers),
            "ACT_AUTH": "none",
            "ACT_SPEND_LEDGER": str(self.guard.ledger),
            "ACT_SPEND_CAP_USD": str(self.guard.cap),
            "ACT_RUN_TOKEN": self.token,
            "PYTHONDONTWRITEBYTECODE": "1",
        }
        (self.run_dir / "logs").mkdir(exist_ok=True)
        for n, p in zip(self.names, ports, strict=True):
            out = open(self.run_dir / "logs" / f"{n}.out", "w")
            self.procs[n] = subprocess.Popen(
                [sys.executable, "-m", "act_teams.server", "--agent", n, "--port", str(p)], env=env, stdout=out, stderr=subprocess.STDOUT
            )
        deadline = time.time() + timeout
        pending = set(self.names)
        while pending and time.time() < deadline:
            for n in list(pending):
                if self.procs[n].poll() is not None:
                    raise RuntimeError(f"agent {n} exited with {self.procs[n].returncode}; see {self.run_dir / 'logs' / (n + '.out')}")
                try:
                    if httpx.get(self.urls[n] + "ping", timeout=1.0).status_code == 200:
                        pending.discard(n)
                except httpx.HTTPError:
                    pass
            time.sleep(0.2)
        if pending:
            raise TimeoutError(f"agents not ready after {timeout}s: {sorted(pending)}")

    def stop(self) -> None:
        for p in self.procs.values():
            p.terminate()
        for p in self.procs.values():
            try:
                p.wait(timeout=10)
            except subprocess.TimeoutExpired:
                p.kill()
        self.procs.clear()

    def __enter__(self) -> LocalTeam:
        self.start()
        return self

    def __exit__(self, *a) -> None:
        self.stop()

    def client(self, caller: str, directory: dict[str, str] | None = None, policy: AllowPolicy | None = None) -> A2AClient:
        return A2AClient(caller, policy or self.policy, directory or self.urls, NoAuth())

    async def task(self, entry: str, text: str) -> str:
        """Start a task as the external caller `user` (allowed only on the entry agents)."""
        os.environ["ACT_RUN_TOKEN"] = self.token
        return await self.client(USER).send(entry, text)

    def raw_post(self, callee: str, claimed_caller: str, text: str = "hi", token: bool = True) -> httpx.Response:
        """A hand-made JSON-RPC call that claims to come from `claimed_caller` (used by the must-fail controls)."""
        body = {
            "jsonrpc": "2.0",
            "id": "x",
            "method": "message/send",
            "params": {"message": {"role": "user", "parts": [{"kind": "text", "text": text}], "messageId": uuid.uuid4().hex}},
        }
        headers = {CALLER_HEADER: claimed_caller, "Content-Type": "application/json"}
        if token:
            headers[TOKEN_HEADER] = self.token
        return httpx.post(self.urls[callee], json=body, headers=headers, timeout=60)

    def spent(self) -> float:
        return self.guard.total()


def main(argv: list[str] | None = None) -> None:
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest="cmd", required=True)
    r = sub.add_parser("run")
    r.add_argument("--config", default="team.yaml")
    r.add_argument("--task", required=True)
    r.add_argument("--entry", default=None)
    r.add_argument("--agents", default=None, help="comma separated; default all")
    r.add_argument("--cap", type=float, default=2.0)
    a = ap.parse_args(argv)
    cfg = load(a.config)
    entry = a.entry or sorted(AllowPolicy.from_config(cfg).peers_of(USER))[0]
    with LocalTeam(cfg, a.config, a.agents.split(",") if a.agents else None, cap_usd=a.cap) as t:
        print(f"{len(t.names)} agents up; run dir {t.run_dir}", flush=True)
        reply = asyncio.run(t.task(entry, a.task))
        print(reply)
        print(f"spent ${t.spent():.6f} of cap ${t.guard.cap:.2f}")


if __name__ == "__main__":
    main()
