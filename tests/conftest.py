import copy
import os
from pathlib import Path

import pytest
import yaml

from act_teams.local import scrub_aws_env

ROOT = Path(__file__).resolve().parents[1]


@pytest.fixture
def raw():
    return copy.deepcopy(yaml.safe_load((ROOT / "team.yaml").read_text()))


@pytest.fixture
def cfg():
    from act_teams.config import load

    return load(ROOT / "team.yaml")


@pytest.fixture(autouse=True)
def no_aws_from_tests(monkeypatch):
    """No test can reach AWS: no credentials, no profile, no secret id, instance metadata off (a stray call came from ACT_OPENROUTER_SECRET_ID)."""
    scrubbed = scrub_aws_env(dict(os.environ))
    for k in list(os.environ):
        if k not in scrubbed:
            monkeypatch.delenv(k)
    for k, v in scrubbed.items():
        monkeypatch.setenv(k, v)
