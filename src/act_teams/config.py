"""Load and validate team.yaml. The same file is read by Terraform (infra/locals.tf)."""

from __future__ import annotations

import re
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

import yaml

NAME_RE = re.compile(r"^[a-z][a-z0-9-]{0,30}$")
AUTH_MODES = ("none", "sigv4", "bearer")
KNOWN_TOOLS = ("calculator", "ask_peer", "word_count")


class ConfigError(ValueError):
    """team.yaml is not valid. The message names the field."""


@dataclass(frozen=True)
class ModelSpec:
    key: str
    id: str
    max_tokens: int
    price_in_per_m: float
    price_out_per_m: float


@dataclass(frozen=True)
class AgentSpec:
    name: str
    role: str
    model: ModelSpec
    prompt: str
    tools: tuple[str, ...]


@dataclass(frozen=True)
class Rule:
    source: str  # "from" in the file
    target: str  # "to"


@dataclass(frozen=True)
class TeamConfig:
    project: str
    region: str
    auth: str
    rules: tuple[Rule, ...]
    entry: tuple[str, ...] = ()  # selectors the external caller `user` may call
    agents: dict[str, AgentSpec] = field(default_factory=dict)
    roles: dict[str, tuple[str, ...]] = field(default_factory=dict)
    runtime: dict[str, Any] = field(default_factory=dict)

    def agent(self, name: str) -> AgentSpec:
        try:
            return self.agents[name]
        except KeyError:
            raise ConfigError(f"unknown agent {name!r}") from None


def _expand(selector: str, roles: dict[str, tuple[str, ...]], agents: dict[str, AgentSpec], where: str) -> tuple[str, ...]:
    if selector.startswith("role:"):
        role = selector[5:]
        if role not in roles:
            raise ConfigError(f"{where}: unknown role {role!r}")
        return roles[role]
    if selector not in agents:
        raise ConfigError(f"{where}: unknown agent {selector!r} (use an agent name or role:<role>; wildcards are not allowed)")
    return (selector,)


def load(path: str | Path) -> TeamConfig:
    raw = yaml.safe_load(Path(path).read_text())
    return parse(raw)


def parse(raw: dict[str, Any]) -> TeamConfig:
    if not isinstance(raw, dict):
        raise ConfigError("team.yaml must be a mapping")
    for key in ("project", "region", "a2a", "models", "roles"):
        if key not in raw:
            raise ConfigError(f"missing top-level key {key!r}")
    a2a = raw["a2a"] or {}
    auth = a2a.get("auth", "sigv4")
    if auth not in AUTH_MODES:
        raise ConfigError(f"a2a.auth must be one of {AUTH_MODES}, got {auth!r}")
    models = {}
    for key, m in raw["models"].items():
        if m["id"].endswith(":free") or "stealth" in m["id"]:
            raise ConfigError(f"models.{key}: free and stealth models log prompts and are not allowed")
        models[key] = ModelSpec(key, m["id"], int(m["max_tokens"]), float(m["price_in_per_m"]), float(m["price_out_per_m"]))
    agents: dict[str, AgentSpec] = {}
    roles: dict[str, tuple[str, ...]] = {}
    for role, r in raw["roles"].items():
        if r["model"] not in models:
            raise ConfigError(f"roles.{role}: unknown model {r['model']!r}")
        names = []
        for entry in r["agents"]:
            e = {"name": entry} if isinstance(entry, str) else dict(entry)
            name = e["name"]
            if not NAME_RE.match(name):
                raise ConfigError(f"agent name {name!r} must match {NAME_RE.pattern}")
            if name in agents:
                raise ConfigError(f"duplicate agent name {name!r}")
            if name.startswith("role:") or name in roles:
                raise ConfigError(f"agent name {name!r} clashes with a role selector")
            model_key = e.get("model", r["model"])
            if model_key not in models:
                raise ConfigError(f"agent {name}: unknown model {model_key!r}")
            tools = tuple(e.get("tools", r.get("tools", [])))
            for t in tools:
                if t not in KNOWN_TOOLS:
                    raise ConfigError(f"agent {name}: unknown tool {t!r}; known: {KNOWN_TOOLS}")
            agents[name] = AgentSpec(name, role, models[model_key], e.get("prompt", r["prompt"]).strip(), tools)
            names.append(name)
        if not names:
            raise ConfigError(f"roles.{role} has no agents")
        roles[role] = tuple(names)
    clash = set(roles) & set(agents)
    if clash:
        raise ConfigError(f"names used both as role and agent: {sorted(clash)}")
    rules = []
    for i, rule in enumerate(a2a.get("allow") or []):
        if set(rule) != {"from", "to"}:
            raise ConfigError(f"a2a.allow[{i}] needs exactly the keys from and to")
        rules.append(Rule(rule["from"], rule["to"]))
        _expand(rule["from"], roles, agents, f"a2a.allow[{i}].from")
        _expand(rule["to"], roles, agents, f"a2a.allow[{i}].to")
    entry = tuple(a2a.get("entry") or [])
    for i, e in enumerate(entry):
        _expand(e, roles, agents, f"a2a.entry[{i}]")
    return TeamConfig(raw["project"], raw["region"], auth, tuple(rules), entry, agents, roles, raw.get("runtime", {}))
