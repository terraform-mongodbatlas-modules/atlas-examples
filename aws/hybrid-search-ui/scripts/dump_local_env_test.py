from __future__ import annotations

from dump_local_env import local_env_from_secret, render_env_file

_SECRET = {
    "aws_region": "us-east-1",
    "container": {
        "env": {
            "MONGODB_URI": "mongodb+srv://iam@cluster/?authMechanism=MONGODB-AWS",
            "MONGODB_DATABASE": "hybrid_search",
            "AUTOEMBED_MODEL": "voyage-4-lite",
            "ENABLE_LLM": "true",
            "LLM_PROVIDER": "anthropic",
            "SKIP_INDEX_CREATION": "true",
            "TOP_K": "20",
            "CHUNK_MAX_TOKENS": "512",
            "CHAINLIT_DEMO_USERNAME": "demo",
        },
        "secret_keys": [
            "CHAINLIT_AUTH_SECRET",
            "CHAINLIT_DEMO_PASSWORD",
            "ANTHROPIC_API_KEY",
        ],
    },
    "CHAINLIT_AUTH_SECRET": "auth",
    "CHAINLIT_DEMO_PASSWORD": "demo-pass",
    "ANTHROPIC_API_KEY": "llm-key",
}


def test_maps_public_uri_and_drops_chainlit() -> None:
    env, warnings = local_env_from_secret(
        _SECRET,
        mongodb_uri="mongodb+srv://debug:pass@cluster/hybrid_search",
    )
    assert warnings == []
    assert env["MONGODB_URI"] == "mongodb+srv://debug:pass@cluster/hybrid_search"
    assert env["ANTHROPIC_API_KEY"] == "llm-key"
    assert env["AUTOEMBED_MODEL"] == "voyage-4-lite"
    assert "VOYAGE_API_KEY" not in env
    assert "VOYAGE_BASE_URL" not in env
    assert env["SKIP_INDEX_CREATION"] == "false"
    assert env["TOP_K"] == "20"
    assert env["CHUNK_MAX_TOKENS"] == "512"
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
    rendered = render_env_file(env, secret_name="hybrid-search-ui-app")
    assert 'MONGODB_URI="mongodb+srv://user:pass@\\"host\\"/db"' in rendered
    assert "# Source secret: hybrid-search-ui-app" in rendered


def test_bedrock_env_keys_flow_through() -> None:
    secret = {
        "aws_region": "us-east-1",
        "container": {
            "env": {
                "MONGODB_DATABASE": "hybrid_search",
                "AUTOEMBED_MODEL": "voyage-4-lite",
                "ENABLE_LLM": "true",
                "LLM_PROVIDER": "bedrock",
                "BEDROCK_MODEL": "amazon.nova-lite-v1:0",
                "AWS_REGION": "us-east-1",
                "TOP_K": "20",
                "CHUNK_MAX_TOKENS": "512",
            },
            "secret_keys": [
                "CHAINLIT_AUTH_SECRET",
                "CHAINLIT_DEMO_PASSWORD",
            ],
        },
    }
    env, _ = local_env_from_secret(secret, mongodb_uri="mongodb+srv://debug:pass@cluster/db")
    assert env["LLM_PROVIDER"] == "bedrock"
    assert env["BEDROCK_MODEL"] == "amazon.nova-lite-v1:0"
    assert env["AWS_REGION"] == "us-east-1"
    assert env["CHUNK_MAX_TOKENS"] == "512"
    rendered = render_env_file(env, secret_name="hybrid-search-ui-app")
    assert (
        rendered.index("LLM_PROVIDER=")
        < rendered.index("BEDROCK_MODEL=")
        < rendered.index("AWS_REGION=")
    )
    assert rendered.index("TOP_K=") < rendered.index("CHUNK_MAX_TOKENS=")
