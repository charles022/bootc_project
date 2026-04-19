#!/usr/bin/env python3

# Import required modules for the startup smoke test. # import modules
import sys # provide stderr and exits
import time # provide timing visibility

# Try importing torch so the container validates its Python stack. # torch import block
try: # begin guarded import
    import torch # import pytorch
except Exception as exc: # catch import failure
    print(f"ERROR: failed to import torch: {exc}", file=sys.stderr, flush=True) # report import error
    raise SystemExit(1) # exit nonzero on failure

# Emit a clear startup marker. # test banner
print("=== dev_container_test.py starting ===", flush=True) # start marker

# Report the installed torch version. # torch version output
print(f"torch_version={torch.__version__}", flush=True) # print torch version

# Report CUDA visibility. # cuda status output
print(f"cuda_available={torch.cuda.is_available()}", flush=True) # print CUDA availability

# Print the first GPU name if CUDA is visible. # gpu info output
if torch.cuda.is_available(): # only run when CUDA is available
    print(f"gpu_name={torch.cuda.get_device_name(0)}", flush=True) # print GPU name

# Sleep briefly so logs are easy to read in order. # readability pause
time.sleep(1) # short delay

# Emit a clear completion marker. # test footer
print("=== dev_container_test.py completed ===", flush=True) # completion marker
