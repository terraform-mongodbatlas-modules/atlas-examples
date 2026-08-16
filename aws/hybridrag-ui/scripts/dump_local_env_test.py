from __future__ import annotations

from dump_local_env import local_env_from_secret, render_env_file

_SECRET = {
    "aws_region": "us-east-1",
    "container": {
        "env": {
            "MONGODB_URI": "mongodb+srv://iam@cluster/?authMechanism=MONGODB-AWS",
            "MONGODB_DATABASE": "hybridrag",
            "VOYAGE_BASE_URL": "https://ai.mongodb.com/v1",
            "ENABLE_LLM": "true",
            "LLM_PROVIDER": "anthropic",
            "SKIP_INDEX_CREATION": "true",
            "DEFAULT_QUERY_MODE": "mix",
            "DEFAULT_TOP_K": "60",
            "DEFAULT_RERANK_TOP_K": "10",
            "ENABLE_RERANK": "true",
            "ENABLE_ENTITY_BOOSTING": "true",
            "ENABLE_IMPLICIT_EXPANSION": "true",
            "CHAINLIT_DEMO_USERNAME": "demo",
        },
        "secret_keys": [
            "VOYAGE_API_KEY",
            "CHAINLIT_AUTH_SECRET",
            "CHAINLIT_DEMO_PASSWORD",
            "ANTHROPIC_API_KEY",
        ],
    },
    "VOYAGE_API_KEY": "voyage-key",
    "CHAINLIT_AUTH_SECRET": "auth",
    "CHAINLIT_DEMO_PASSWORD": "demo-pass",
    "ANTHROPIC_API_KEY": "llm-key",
}


def test_maps_public_uri_and_drops_chainlit() -> None:
    env, warnings = local_env_from_secret(
        _SECRET,
        mongodb_uri="mongodb+srv://debug:pass@cluster/hybridrag",
    )
    assert warnings == []
    assert env["MONGODB_URI"] == "mongodb+srv://debug:pass@cluster/hybridrag"
    assert env["VOYAGE_API_KEY"] == "voyage-key"
    assert env["ANTHROPIC_API_KEY"] == "llm-key"
    assert env["SKIP_INDEX_CREATION"] == "true"
    assert env["DEFAULT_QUERY_MODE"] == "mix"
    assert "CHAINLIT_AUTH_SECRET" not in env
    assert "CHAINLIT_DEMO_PASSWORD" not in env
    assert "CHAINLIT_DEMO_USERNAME" not in env


def test_warns_without_public_uri() -> None:
    env, warnings = local_env_from_secret(_SECRET, mongodb_uri=None)
    assert "MONGODB_URI" not in env
    assert len(warnings) == 1
    assert "public_debug_access" in warnings[0]


def test_render_env_file_quotes_values() -> None:
    env, _ = local_env_from_secret(
        _SECRET,
        mongodb_uri='mongodb+srv://user:pass@"host"/db',
    )
    rendered = render_env_file(env, secret_name="hybridrag-ui-app")
    assert 'MONGODB_URI="mongodb+srv://user:pass@\\"host\\"/db"' in rendered
    assert "# Source secret: hybridrag-ui-app" in rendered
