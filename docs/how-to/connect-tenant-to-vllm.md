# Connect a tenant agent to local vLLM

By default, every tenant agent created via `agentctl agent_create` (or `platformctl agent create`) is already pointed at the host's local vLLM server. There is **nothing to configure** for the default case.

## What's wired by default

The agent runtime container (`agent-openclaw-runtime`) is rendered with these environment variables:

```ini
OPENAI_BASE_URL=http://host.containers.internal:8000/v1
OPENAI_MODEL=Qwen3-8B-Q4_K_M
OPENAI_API_KEY=local-vllm
```

`host.containers.internal` resolves to the host loopback gateway from inside a rootless Podman container. The `OPENAI_API_KEY` value is a non-empty placeholder — vLLM is configured to ignore it, but some OpenAI client libraries refuse to start without something set.

Smoke-test from inside an agent shell:

```bash
curl -s "$OPENAI_BASE_URL/models" | jq
```

You should see `Qwen3-8B-Q4_K_M` in the response.

## Using an external provider for a specific agent

If a particular agent needs to talk to a remote provider (OpenAI, Anthropic, etc.) instead of, or in addition to, local vLLM:

1. As the tenant service account, create a rootless Podman secret with the provider key:

   ```bash
   printf '%s' "$YOUR_PROVIDER_KEY" | podman secret create my-provider-key -
   ```

2. Author a per-agent Quadlet override that mounts the secret as `OPENAI_API_KEY` and overrides `OPENAI_BASE_URL` and `OPENAI_MODEL`. Place the override in the tenant's user Quadlet directory and `systemctl --user daemon-reload`.

3. Restart the agent.

The platform never sees the secret. It lives in the tenant's own rootless Podman secret store and is mounted only into the tenant's own agent containers.

## What the platform does *not* do

- It does not mint, rotate, or revoke external-provider API keys.
- It does not log or rate-limit calls to local vLLM or to external providers.
- It does not maintain a registry of which models a tenant is allowed to use.

The host owns one capability — a local model server on a loopback port. Anything beyond that is the tenant's responsibility.

## See also

- `reference/vllm.md`
- `reference/tenant_quadlets.md`
- `concepts/credential_broker.md` (broker scope: OAuth-style platform credentials, not LLM API keys)
