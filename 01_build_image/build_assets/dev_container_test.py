#!/usr/bin/env python3

import os
import sys
import time

try:
    import torch
except Exception as exc:
    print(f"ERROR: failed to import torch: {exc}", file=sys.stderr, flush=True)
    raise SystemExit(1)

print("=== dev_container_test.py starting ===", flush=True)

cuda_available = torch.cuda.is_available()
print(f"torch_version={torch.__version__}", flush=True)
print(f"cuda_available={cuda_available}", flush=True)

if os.environ.get("REQUIRE_CUDA", "1") != "0" and not cuda_available:
    print("ERROR: CUDA is required but not available", file=sys.stderr, flush=True)
    raise SystemExit(1)

if cuda_available:
    print(f"gpu_name={torch.cuda.get_device_name(0)}", flush=True)

time.sleep(1)

print("=== dev_container_test.py completed ===", flush=True)
