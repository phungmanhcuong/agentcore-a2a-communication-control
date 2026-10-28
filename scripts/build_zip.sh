#!/usr/bin/env bash
# Build the AgentCore direct-code package: linux arm64 wheels for Python 3.13 (the platform AgentCore Runtime uses), main.py and team.yaml at the zip root.
# Output: build/agent.zip (limit 250 MB for direct code deployment). Needs uv; runs on any host, no Docker.
set -euo pipefail
cd "$(dirname "$0")/.."
rm -rf build && mkdir -p build/pkg
uv pip install --quiet --target build/pkg --python-platform aarch64-manylinux2014 --python-version 3.13 --no-cache .
cp main.py team.yaml build/pkg/
find build/pkg -name '__pycache__' -type d -prune -exec rm -rf {} +
find build/pkg -type d -exec chmod 755 {} + && find build/pkg -type f -exec chmod 644 {} +   # POSIX permissions matter for AgentCore
(cd build/pkg && python3 - <<'PY'
import os, zipfile
with zipfile.ZipFile("../agent.zip", "w", zipfile.ZIP_DEFLATED, compresslevel=6) as z:
    for dp, _, fns in os.walk("."):
        for fn in sorted(fns):
            p = os.path.join(dp, fn)
            z.write(p, os.path.relpath(p, "."))
PY
)
python3 - <<'PY'
import os
size = os.path.getsize("build/agent.zip") / 1e6
print(f"build/agent.zip {size:.1f} MB (limit 250 MB)")
raise SystemExit(0 if size < 250 else 1)
PY
