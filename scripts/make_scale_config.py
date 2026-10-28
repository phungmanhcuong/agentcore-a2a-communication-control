#!/usr/bin/env python3
"""Write a copy of team.yaml with N agents per role (default 10): planner-1..N, worker-1..N, reviewer-1..N.
Usage: python scripts/make_scale_config.py OUT.yaml [N]"""

import sys
from pathlib import Path

import yaml

src = yaml.safe_load(Path(__file__).resolve().parents[1].joinpath("team.yaml").read_text())
n = int(sys.argv[2]) if len(sys.argv) > 2 else 10
for role, r in src["roles"].items():
    r["agents"] = [f"{role}-{i}" for i in range(1, n + 1)]
Path(sys.argv[1]).write_text(yaml.safe_dump(src, sort_keys=False))
print(f"wrote {sys.argv[1]}: {len(src['roles'])} roles x {n} agents")
