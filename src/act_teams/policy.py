"""The allow policy: deny by default. Used by the A2A client tool, the A2A server middleware and the tests; Terraform expands the
same rules in infra/locals.tf."""

from __future__ import annotations

from dataclasses import dataclass

from .config import TeamConfig, _expand

USER = "user"  # pseudo-caller for the person or script that starts a task


class A2ADenied(PermissionError):
    """A call is not allowed by team.yaml a2a.allow."""


@dataclass(frozen=True)
class AllowPolicy:
    pairs: frozenset[tuple[str, str]]  # (caller, callee), expanded to agent names

    @classmethod
    def from_config(cls, cfg: TeamConfig) -> AllowPolicy:
        pairs: set[tuple[str, str]] = set()
        for i, rule in enumerate(cfg.rules):
            for src in _expand(rule.source, cfg.roles, cfg.agents, f"a2a.allow[{i}].from"):
                for dst in _expand(rule.target, cfg.roles, cfg.agents, f"a2a.allow[{i}].to"):
                    if src != dst:
                        pairs.add((src, dst))
        for i, sel in enumerate(cfg.entry):  # the external caller "user" may call the entry agents only
            for dst in _expand(sel, cfg.roles, cfg.agents, f"a2a.entry[{i}]"):
                pairs.add((USER, dst))
        return cls(frozenset(pairs))

    def allows(self, caller: str, callee: str) -> bool:
        return (caller, callee) in self.pairs

    def check(self, caller: str, callee: str) -> None:
        if not self.allows(caller, callee):
            raise A2ADenied(f"{caller!r} is not allowed to call {callee!r} (a2a.allow, deny by default)")

    def peers_of(self, caller: str) -> tuple[str, ...]:
        return tuple(sorted(dst for src, dst in self.pairs if src == caller))

    def callers_of(self, callee: str) -> tuple[str, ...]:
        return tuple(sorted(src for src, dst in self.pairs if dst == callee))
