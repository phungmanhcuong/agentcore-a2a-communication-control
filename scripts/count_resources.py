#!/usr/bin/env python3
"""Count the resources `terraform apply` will create, by type, from the code: every `resource` block times its for_each.
Understood for_each expressions: none (1), local.agents (one per agent), data.aws_iam_policy_document.invoke (one per agent with allowed peers).
Any other expression stops the script (exit 1) rather than guessing. Writes docs/results/resource_count.json.
Usage: python scripts/count_resources.py [team.yaml] [infra dir]"""

import collections
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "src"))
from act_teams.config import load  # noqa: E402
from act_teams.policy import AllowPolicy  # noqa: E402

BLOCK = re.compile(r'^(resource|data)\s+"([^"]+)"\s+"([^"]+)"\s*\{', re.MULTILINE)


def blocks(text: str):
    for m in BLOCK.finditer(text):
        depth, i = 0, m.end() - 1
        while True:
            if text[i] == "{":
                depth += 1
            elif text[i] == "}":
                depth -= 1
                if depth == 0:
                    break
            i += 1
        yield m.group(1), m.group(2), m.group(3), text[m.end() : i]


def multiplicity(body: str, cfg, policy) -> int:
    m = re.search(r"^\s{2}for_each\s*=\s*(.+)$", body, re.MULTILINE)
    if re.search(r"^\s{2}count\s*=", body, re.MULTILINE):
        raise SystemExit("count = is not understood by this counter")
    if not m:
        return 1
    expr = m.group(1).strip()
    if expr == "local.agents":
        return len(cfg.agents)
    if expr == "data.aws_iam_policy_document.invoke":
        return sum(1 for a in cfg.agents if policy.peers_of(a))
    raise SystemExit(f"for_each expression not understood: {expr!r}")


def count(team: Path, infra: Path) -> dict:
    cfg = load(team)
    policy = AllowPolicy.from_config(cfg)
    res, data = collections.Counter(), collections.Counter()
    for tf in sorted(infra.glob("*.tf")):
        for kind, typ, _name, body in blocks(tf.read_text()):
            (res if kind == "resource" else data)[typ] += multiplicity(body, cfg, policy) if kind == "resource" else 1
    return {
        "agents": len(cfg.agents),
        "resources_by_type": dict(sorted(res.items())),
        "resources_total": sum(res.values()),
        "data_sources_by_type": dict(sorted(data.items())),
    }


if __name__ == "__main__":
    team = Path(sys.argv[1]) if len(sys.argv) > 1 else ROOT / "team.yaml"
    infra = Path(sys.argv[2]) if len(sys.argv) > 2 else ROOT / "infra"
    out = count(team, infra)
    if len(sys.argv) <= 1:
        (ROOT / "docs/results").mkdir(parents=True, exist_ok=True)
        (ROOT / "docs/results/resource_count.json").write_text(json.dumps(out, indent=1))
    print(json.dumps(out, indent=1))
