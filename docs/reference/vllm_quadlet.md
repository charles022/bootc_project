# Shared vLLM Quadlet — reference

The shared vLLM service (see `docs/concepts/inference_stack.md`) is delivered through five files in the host image and one runtime-generated env file.

## `01_build_image/build_assets/vllm-internal.network`

Path on host: `/usr/share/containers/systemd/vllm-internal.network`
Purpose: declares the internal podman network used by vLLM and every tenant agent pod.
Key fields:
- `NetworkName=vllm-internal`
- `Internal=true` — no default route, vLLM cannot egress, host's default network cannot reach it.
- `Subnet=10.89.42.0/24`

## `01_build_image/build_assets/vllm.container`

Path on host: `/usr/share/containers/systemd/vllm.container`
Purpose: the shared vLLM OpenAI-compatible inference service.
Key fields:
- `Image=docker.io/vllm/vllm-openai:latest` (override via `VLLM_IMAGE` in the env file).
- `Network=vllm-internal.network` — the only network attachment.
- `AddDevice=nvidia.com/gpu=all` — GPU access via CDI, mirrors the dev pod.
- `EnvironmentFile=/etc/openclaw-platform/vllm.env` — model name, key, quotas.
- `ReadOnly=true`, `NoNewPrivileges=true`, `DropCapability=ALL`, tmpfs `/tmp` and `/dev/shm`.
- `Volume=vllm-models.volume:/root/.cache/huggingface:Z` — persists weights.
- `Exec=` line passes `--model`, `--api-key`, `--max-num-seqs`, `--gpu-memory-utilization` from the env file.

## `01_build_image/build_assets/vllm-models.volume`

Path on host: `/usr/share/containers/systemd/vllm-models.volume`
Purpose: named podman volume backing the HuggingFace model cache so weights download once and survive restarts.

## `01_build_image/build_assets/vllm-bootstrap.service`

Path on host: `/usr/lib/systemd/system/vllm-bootstrap.service`
Purpose: oneshot that generates `/etc/openclaw-platform/vllm.env` if it does not already exist. Runs before `vllm.service`.
Key fields:
- `ConditionPathExists=!/etc/openclaw-platform/vllm.env` — idempotent; only the first boot runs it.
- `ExecStart=/usr/local/bin/vllm-bootstrap.sh`.

## `01_build_image/build_assets/vllm-bootstrap.sh`

Path on host: `/usr/local/bin/vllm-bootstrap.sh`
Purpose: writes `/etc/openclaw-platform/vllm.env` with a fresh 48-character random API key and defaults: `VLLM_IMAGE`, `VLLM_MODEL=Qwen/Qwen2.5-7B-Instruct`, `VLLM_MAX_NUM_SEQS=32`, `VLLM_GPU_MEMORY_UTILIZATION=0.85`.
Notes: file is mode 0600 root:root. Operators may rewrite it to pin different values; the script will not overwrite an existing file.

## `/etc/openclaw-platform/vllm.env` (runtime-generated)

Purpose: single source of truth for the vLLM service's runtime configuration.
Notes: not in the OCI image. Generated on first boot. Read by `vllm.container` via `EnvironmentFile=`. Operators may edit and `systemctl restart vllm.service` to apply.

## Agent-side wiring

- `agent.pod.tmpl` attaches every agent pod to `vllm-internal.network`.
- `agent-openclaw-runtime.container.tmpl` exports `OPENAI_BASE_URL`, `OPENAI_API_BASE`, `OPENCLAW_INFERENCE_ENDPOINT=http://vllm:8000/v1`, and `OPENCLAW_INFERENCE_CREDENTIAL_ID=vllm` so the runtime knows where and how to authenticate.
- `openclaw-provisioner.py` adds `vllm` to `ALLOWED_CREDENTIALS_DEFAULT` and `vllm-only`, `vllm+messaging` to `ALLOWED_NETWORKS_DEFAULT` so policy files can reference them.

## See also

- `docs/concepts/inference_stack.md` — design and threat model.
- `docs/reference/quadlets.md` — index of all Quadlet artifacts.
- `docs/reference/systemd_units.md` — index of host systemd units.
