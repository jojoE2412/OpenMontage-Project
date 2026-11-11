"""Host hardware facts used to explain local model compatibility."""

from __future__ import annotations

import importlib.util
import os
import platform
import shutil
import subprocess
from functools import lru_cache
from typing import Any


def _memory_total_mb() -> int | None:
    if os.name == "nt":
        import ctypes
        from ctypes import wintypes

        class MemoryStatus(ctypes.Structure):
            _fields_ = [
                ("dwLength", wintypes.DWORD), ("dwMemoryLoad", wintypes.DWORD),
                ("ullTotalPhys", ctypes.c_ulonglong), ("ullAvailPhys", ctypes.c_ulonglong),
                ("ullTotalPageFile", ctypes.c_ulonglong), ("ullAvailPageFile", ctypes.c_ulonglong),
                ("ullTotalVirtual", ctypes.c_ulonglong), ("ullAvailVirtual", ctypes.c_ulonglong),
                ("ullAvailExtendedVirtual", ctypes.c_ulonglong),
            ]

        status = MemoryStatus()
        status.dwLength = ctypes.sizeof(status)
        if ctypes.windll.kernel32.GlobalMemoryStatusEx(ctypes.byref(status)):
            return int(status.ullTotalPhys // (1024 * 1024))
        return None
    try:
        page_size = os.sysconf("SC_PAGE_SIZE")
        pages = os.sysconf("SC_PHYS_PAGES")
        return int(page_size * pages // (1024 * 1024))
    except (AttributeError, OSError, ValueError):
        return None


def _gpu_facts() -> dict[str, Any]:
    executable = shutil.which("nvidia-smi")
    if executable is None:
        return {"available": False, "name": None, "vram_mb": None, "driver_version": None}
    try:
        result = subprocess.run(
            [executable, "--query-gpu=name,memory.total,driver_version", "--format=csv,noheader,nounits"],
            capture_output=True, text=True, timeout=4, check=True,
        )
        first = result.stdout.strip().splitlines()[0].split(",")
        return {
            "available": True,
            "name": first[0].strip(),
            "vram_mb": int(float(first[1].strip())),
            "driver_version": first[2].strip() if len(first) > 2 else None,
        }
    except (OSError, subprocess.SubprocessError, IndexError, ValueError):
        return {"available": False, "name": None, "vram_mb": None, "driver_version": None}


def _cuda_facts() -> dict[str, Any]:
    if importlib.util.find_spec("torch") is None:
        return {"available": False, "runtime_version": None, "reason": "PyTorch is not installed"}
    try:
        import torch

        return {
            "available": bool(torch.cuda.is_available()),
            "runtime_version": torch.version.cuda,
            "reason": None if torch.cuda.is_available() else "PyTorch cannot access CUDA",
        }
    except Exception as exc:  # the diagnostic must not make the API unavailable
        return {"available": False, "runtime_version": None, "reason": str(exc)[:240]}


@lru_cache(maxsize=1)
def detect_host_hardware() -> dict[str, Any]:
    gpu = _gpu_facts()
    return {
        "cpu": {"name": platform.processor() or platform.machine(), "logical_cores": os.cpu_count()},
        "ram_mb": _memory_total_mb(),
        "gpu": gpu,
        "cuda": _cuda_facts(),
    }
