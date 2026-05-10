# vLLM

The host image ships a single shared vLLM OpenAI-compatible API server, run as a system Quadlet. Tenant agents default to it for chat-completion calls without any per-tenant configuration.

## Topology

```text
vllm.container (system Quadlet, rootful)
  └── publishes 127.0.0.1:8000 only
  └── runs as the baked-in `vllm` system user
  └── consumes /etc/cdi/nvidia.yaml after nvidia-cdi-refresh.service
  └── volume → /var/lib/openclaw-platform/vllm-cache  (vllm:vllm 0750)

tenant agent runtime container (rootless, per-tenant user)
  └── OPENAI_BASE_URL = http://host.containers.internal:8000/v1
  └── OPENAI_MODEL    = Qwen3-8B-Q4_K_M
  └── OPENAI_API_KEY  = local-vllm     (placeholder; vLLM does not validate)
```

vLLM does not run with `--api-key`. The loopback bind is the boundary: only host-local processes (and rootless tenant containers via `host.containers.internal`) can reach it.

## Files

| Path in repo | Path in host image | Role |
| --- | --- | --- |
| `01_build_image/build_assets/vllm.container` | `/usr/share/containers/systemd/vllm.container` | System Quadlet, generates `vllm.service`. |
| `01_build_image/build_assets/vllm.sysusers.conf` | `/usr/lib/sysusers.d/vllm.conf` | Creates the `vllm` system user at first boot. |
| `01_build_image/build_assets/vllm.tmpfiles.conf` | `/usr/lib/tmpfiles.d/vllm.conf` | Owns the cache directory at `/var/lib/openclaw-platform/vllm-cache` as `vllm:vllm 0750`. |

## Quadlet field walkthrough

```ini
[Unit]
After=network-online.target nvidia-cdi-refresh.service
Requires=nvidia-cdi-refresh.service

[Container]
Image=docker.io/vllm/vllm-openai:latest
User=vllm
Group=vllm
PublishPort=127.0.0.1:8000:8000
PodmanArgs=--ipc=host
PodmanArgs=--device=nvidia.com/gpu=all
PodmanArgs=--security-opt=label=disable
Volume=/var/lib/openclaw-platform/vllm-cache:/home/vllm/.cache:Z
Secret=hf-token,type=env,target=HF_TOKEN
Exec=--model Qwen3-8B-Q4_K_M --host 0.0.0.0 --port 8000 --generation-config vllm
```

* **`Requires=nvidia-cdi-refresh.service`**: the CDI spec must be generated before vLLM tries to attach the GPU.
* **`User=vllm`**: container PID 1 runs as the unprivileged `vllm` uid baked in by `sysusers.d`. Defense-in-depth on top of the loopback boundary.
* **`PublishPort=127.0.0.1:8000:8000`**: binds the API only to the host loopback interface; never exposed on a routable interface.
* **`--device=nvidia.com/gpu=all`**: CDI selector pointing at all GPUs visible to `nvidia-ctk cdi generate`.
* **`--generation-config vllm`**: avoids inheriting sampling defaults from the model's `generation_config.json` on Hugging Face.
* **`Secret=hf-token`**: optional Podman secret. If the operator has not run `podman secret create hf-token -`, gated models will 401; the pinned default (`Qwen3-8B-Q4_K_M`) is open-weight and works without it.

## Model

The served model is **pinned in the Quadlet `Exec=` line**. There is no env file, no operator override, and no scaffolding for multiple models. Switching to a different model is a host-image change: edit `vllm.container`, rebuild the host image, redeploy.

`Qwen3-8B-Q4_K_M` is a GGUF quantization. vLLM's GGUF loader resolves the repo + quant variant; if a future model swap requires a different `--model` argument shape (HF repo + filename selector), update the Quadlet at that time.

## Tenant integration

The tenant agent runtime template (`agent-openclaw-runtime.container.tmpl`) sets the three OpenAI client env vars by default. A tenant who wants to bypass the local server for a specific agent (e.g. talk to Anthropic instead) overrides `OPENAI_BASE_URL` in their per-agent Quadlet override and supplies their own credential as a rootless Podman secret. See `how-to/connect-tenant-to-vllm.md`.

The platform does not mint, store, track, or rate-limit tenant-supplied external-provider keys; those live in the tenant's own rootless `podman secret` store.

## See also

- `reference/quadlets.md`
- `concepts/gpu_stack.md`
- `how-to/connect-tenant-to-vllm.md`
