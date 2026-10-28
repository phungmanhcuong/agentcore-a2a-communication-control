import pytest

from act_teams.config import ConfigError, load, parse
from tests.conftest import ROOT


def test_team_yaml_is_3_roles_x_3_agents():
    cfg = load(ROOT / "team.yaml")
    assert set(cfg.roles) == {"planner", "worker", "reviewer"}
    assert all(len(v) == 3 for v in cfg.roles.values())
    assert len(cfg.agents) == 9
    assert cfg.agent("worker-2").model.id == "openai/gpt-oss-20b"
    assert cfg.agent("reviewer-1").tools == ("calculator",)


def mutate(raw, fn):
    fn(raw)
    return raw


@pytest.mark.parametrize(
    "label,fn",
    [
        ("duplicate agent name", lambda r: r["roles"]["worker"]["agents"].append("planner-1")),
        ("unknown role in a rule", lambda r: r["a2a"]["allow"].append({"from": "role:ghost", "to": "role:worker"})),
        ("unknown agent in a rule", lambda r: r["a2a"]["allow"].append({"from": "planner-1", "to": "nobody-9"})),
        ("wildcard target", lambda r: r["a2a"]["allow"].append({"from": "planner-1", "to": "*"})),
        ("rule with an extra key", lambda r: r["a2a"]["allow"].append({"from": "planner-1", "to": "worker-1", "also": "x"})),
        ("bad auth mode", lambda r: r["a2a"].__setitem__("auth", "magic")),
        ("free model", lambda r: r["models"]["worker"].__setitem__("id", "meta-llama/llama-3.3-70b-instruct:free")),
        ("unknown tool", lambda r: r["roles"]["worker"].__setitem__("tools", ["shell"])),
        ("bad agent name", lambda r: r["roles"]["worker"]["agents"].append("Worker_9")),
        ("unknown model", lambda r: r["roles"]["worker"].__setitem__("model", "gold")),
        ("role without agents", lambda r: r["roles"]["worker"].__setitem__("agents", [])),
        ("bad entry selector", lambda r: r["a2a"].__setitem__("entry", ["role:ghost"])),
    ],
)
def test_invalid_config_is_rejected(raw, label, fn):  # must-fail controls: each fault must be refused
    with pytest.raises(ConfigError):
        parse(mutate(raw, fn))


def test_agent_can_override_role_defaults(raw):
    raw["roles"]["worker"]["agents"][0] = {"name": "worker-1", "model": "planner", "tools": ["calculator"]}
    cfg = parse(raw)
    assert cfg.agent("worker-1").model.key == "planner"
    assert cfg.agent("worker-1").tools == ("calculator",)
