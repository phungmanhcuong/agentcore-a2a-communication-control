import pytest

from act_teams.config import parse
from act_teams.policy import USER, A2ADenied, AllowPolicy

ALLOWED = {
    ("planner-1", "worker-1"),
    ("planner-1", "worker-2"),
    ("planner-1", "worker-3"),
    ("planner-2", "worker-1"),
    ("planner-3", "worker-3"),
    ("worker-1", "reviewer-1"),
    ("worker-2", "reviewer-3"),
    ("planner-1", "reviewer-1"),
    (USER, "planner-1"),
    (USER, "planner-3"),
}
DENIED = [
    ("worker-1", "planner-1"),  # backwards
    ("reviewer-1", "worker-1"),  # backwards
    ("planner-2", "reviewer-1"),  # only planner-1 has the direct rule
    ("planner-1", "reviewer-2"),  # the direct rule names reviewer-1 only
    ("planner-1", "planner-2"),  # same role, no rule
    ("worker-1", "worker-2"),
    (USER, "worker-1"),  # the external caller may start a task on planners only
    (USER, "reviewer-1"),
    ("planner-1", "planner-1"),  # never to itself
    ("ghost", "worker-1"),  # unknown caller
]


def test_allowed_pairs(cfg):
    p = AllowPolicy.from_config(cfg)
    for pair in ALLOWED:
        assert p.allows(*pair), pair


@pytest.mark.parametrize("pair", DENIED)
def test_denied_pairs(cfg, pair):  # must-fail: deny by default
    p = AllowPolicy.from_config(cfg)
    assert not p.allows(*pair)
    with pytest.raises(A2ADenied):
        p.check(*pair)


def test_total_pair_count_is_exact(cfg):
    # 3x3 planner->worker (9) + 3x3 worker->reviewer (9) + planner-1->reviewer-1 (1) + 3 user->planner = 22
    assert len(AllowPolicy.from_config(cfg).pairs) == 22


def test_removing_a_rule_refuses_that_pair(raw):  # must-fail control: the check is sensitive to the config
    raw["a2a"]["allow"] = [r for r in raw["a2a"]["allow"] if r["to"] != "role:reviewer" or r["from"] != "role:worker"]
    p = AllowPolicy.from_config(parse(raw))
    assert not p.allows("worker-1", "reviewer-1")
    assert p.allows("planner-1", "worker-1")


def test_empty_allow_and_entry_refuses_everything(raw):
    raw["a2a"]["allow"], raw["a2a"]["entry"] = [], []
    assert AllowPolicy.from_config(parse(raw)).pairs == frozenset()


def test_peers_and_callers(cfg):
    p = AllowPolicy.from_config(cfg)
    assert p.peers_of("worker-2") == ("reviewer-1", "reviewer-2", "reviewer-3")
    assert p.peers_of("reviewer-1") == ()
    assert p.callers_of("reviewer-1") == ("planner-1", "worker-1", "worker-2", "worker-3")
