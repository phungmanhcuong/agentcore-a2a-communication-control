#!/usr/bin/env python3
"""Offline guard for the Terraform IAM: no wildcard in any `actions` or `resources` of a policy statement, and every InvokeAgentRuntime
statement names resources built from the peers map (aws_bedrockagentcore_agent_runtime.agent[...]), never a bare string.
(Principals `*` in the resource-policy Deny are fine: that is how an explicit deny for everyone else is written.)
Usage: python scripts/check_iam_scope.py [infra dir]   exit 0 = clean, 1 = violation"""

import re
import sys
from pathlib import Path

ASSIGN = re.compile(r"^\s*(actions|resources)\s*=\s*(.+)$", re.MULTILINE)


def violations(infra: Path) -> list[str]:
    bad = []
    for tf in sorted(infra.glob("*.tf")):
        text = tf.read_text()
        for m in ASSIGN.finditer(text):
            line = text.count("\n", 0, m.start()) + 1
            kind, val = m.group(1), m.group(2)
            for lit in re.findall(r'"([^"]*)"', val):
                if kind == "actions" and "*" in lit:
                    bad.append(f"{tf.name}:{line}: wildcard in actions: {lit}")
                if kind == "resources" and lit == "*":  # a suffix wildcard inside a named ARN ("${arn}/*", "...-*") is allowed
                    bad.append(f"{tf.name}:{line}: resources contains a bare *")
        if "InvokeAgentRuntime" in text and re.search(r'resources\s*=\s*\["\*"\]', text):
            bad.append(f'{tf.name}: resources = ["*"] next to InvokeAgentRuntime')
    return sorted(set(bad))


if __name__ == "__main__":
    v = violations(Path(sys.argv[1]) if len(sys.argv) > 1 else Path(__file__).resolve().parents[1] / "infra")
    print("\n".join(v) or "no wildcard actions or resources in the Terraform IAM")
    sys.exit(1 if v else 0)
