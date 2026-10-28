#!/usr/bin/env python3
"""Evaluate infra/locals.tf offline (terraform console on a scratch copy with a throw-away LOCAL state; no AWS call, no provider API) and print
the expanded allow rules, peers and runtime names as JSON. tests/test_infra.py compares this with the Python policy.
Usage: python scripts/tf_expansion.py [team.yaml]"""

import json
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
EXPR = "jsonencode({pairs = local.pairs, peers = local.peers, callers = local.callers, entry = local.entry_agents, runtime_name = local.runtime_name, request_headers = local.request_headers})"


def evaluate(team_yaml: Path) -> dict:
    with tempfile.TemporaryDirectory(dir=os.environ.get("TMPDIR")) as d:
        work = Path(d) / "infra"
        shutil.copytree(ROOT / "infra", work, ignore=shutil.ignore_patterns(".terraform", "*.tfstate*"))
        shutil.copy(team_yaml, Path(d) / "team.yaml")
        env = {**os.environ, "TF_IN_AUTOMATION": "1"}
        subprocess.run(
            ["terraform", "init", "-input=false", "-no-color", f"-backend-config=path={d}/scratch.tfstate"],
            cwd=work,
            env=env,
            check=True,
            capture_output=True,
        )
        r = subprocess.run(
            ["terraform", "console", "-no-color"], cwd=work, env=env, input=EXPR + "\n", text=True, capture_output=True, check=True
        )
        out = r.stdout.strip()
        return json.loads(json.loads(out))  # console prints the JSON string as a quoted string


if __name__ == "__main__":
    print(json.dumps(evaluate(Path(sys.argv[1]) if len(sys.argv) > 1 else ROOT / "team.yaml"), indent=1, sort_keys=True))
