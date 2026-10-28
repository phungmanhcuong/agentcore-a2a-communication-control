"""Build the Strands model for an agent: OpenRouter through the OpenAI-compatible provider, data_collection deny on every request."""

from __future__ import annotations

import os
from pathlib import Path

import httpx
from openai import AsyncOpenAI
from strands.models.openai import OpenAIModel

from .config import ModelSpec
from .spend import SpendGuard, SpendTransport

OPENROUTER_URL = "https://openrouter.ai/api/v1"
# Sent on EVERY request: no provider may retain prompts; usage.include makes the API return the cost.
REQUEST_EXTRAS = {"provider": {"data_collection": "deny"}, "usage": {"include": True}}


def read_key() -> str:
    """The key comes from a file named by OPENROUTER_API_KEY_FILE (local) or from the Secrets Manager secret named by ACT_OPENROUTER_SECRET_ID
    (AgentCore). Never from argv, never printed, never in an environment variable value."""
    if os.environ.get("OPENROUTER_API_KEY_FILE"):
        return Path(os.environ["OPENROUTER_API_KEY_FILE"]).read_text().strip()
    secret_id = os.environ["ACT_OPENROUTER_SECRET_ID"]  # KeyError when neither source is configured
    import boto3

    return (
        boto3.client("secretsmanager", region_name=os.environ.get("AWS_REGION"))
        .get_secret_value(SecretId=secret_id)["SecretString"]
        .strip()
    )


def request_params(spec: ModelSpec) -> dict:
    return {"max_tokens": spec.max_tokens, "extra_body": dict(REQUEST_EXTRAS)}


def build_model(
    spec: ModelSpec, who: str, guard: SpendGuard | None = None, transport: httpx.AsyncBaseTransport | None = None
) -> OpenAIModel:
    guard = guard or SpendGuard.from_env()
    http_client = httpx.AsyncClient(transport=SpendTransport(guard, who, transport), timeout=httpx.Timeout(120.0))
    # A pre-built client: the provider closes a client it creates per request, which would close our shared http_client after the first call.
    client = AsyncOpenAI(api_key=read_key(), base_url=OPENROUTER_URL, http_client=http_client)
    return OpenAIModel(
        client=client,
        model_id=spec.id,
        params=request_params(spec),
    )
