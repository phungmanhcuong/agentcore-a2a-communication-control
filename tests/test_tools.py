import pytest

from act_teams.tools import calculator, safe_eval


def test_arithmetic():
    assert safe_eval("(17 + 25) * 3") == 126
    assert safe_eval("2 ** 10 - 1") == 1023


@pytest.mark.parametrize("bad", ["__import__('os').system('id')", "open('/etc/passwd')", "[1,2]", "2 ** 9999", "a + 1", "True + 1"])
def test_non_arithmetic_is_refused(bad):  # must-fail
    with pytest.raises((ValueError, SyntaxError)):
        safe_eval(bad)


def test_tool_returns_error_text_not_exception():
    assert calculator("1/0").startswith("error")
    assert calculator("__import__('os')").startswith("error")
