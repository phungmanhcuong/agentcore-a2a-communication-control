"""Small local tools for the agents."""

from __future__ import annotations

import ast
import operator

from strands import tool

_OPS = {
    ast.Add: operator.add,
    ast.Sub: operator.sub,
    ast.Mult: operator.mul,
    ast.Div: operator.truediv,
    ast.Pow: operator.pow,
    ast.Mod: operator.mod,
    ast.FloorDiv: operator.floordiv,
    ast.USub: operator.neg,
}


def safe_eval(expr: str) -> float:
    """Arithmetic only: numbers, + - * / // % ** and parentheses. Anything else raises ValueError."""

    def ev(n: ast.AST) -> float:
        if isinstance(n, ast.Constant) and isinstance(n.value, (int, float)) and not isinstance(n.value, bool):
            return n.value
        if isinstance(n, ast.BinOp) and type(n.op) in _OPS:
            if isinstance(n.op, ast.Pow) and abs(ev(n.right)) > 100:
                raise ValueError("exponent too large")
            return _OPS[type(n.op)](ev(n.left), ev(n.right))
        if isinstance(n, ast.UnaryOp) and type(n.op) in _OPS:
            return _OPS[type(n.op)](ev(n.operand))
        raise ValueError("only arithmetic is allowed")

    return ev(ast.parse(expr, mode="eval").body)


@tool
def calculator(expression: str) -> str:
    """Evaluate an arithmetic expression such as (17 + 25) * 3.

    Args:
        expression: arithmetic with numbers, + - * / ** % and parentheses
    """
    try:
        return str(safe_eval(expression))
    except (ValueError, SyntaxError, ZeroDivisionError) as e:
        return f"error: {e}"


@tool
def word_count(text: str) -> str:
    """Count the words in a text.

    Args:
        text: the text
    """
    return str(len(text.split()))
