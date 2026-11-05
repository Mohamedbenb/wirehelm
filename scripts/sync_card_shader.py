"""Compatibility entry point; shader ownership lives in the engine module."""
from pathlib import Path
import runpy
runpy.run_path(str(Path(__file__).resolve().parents[1]/"android/liquid-glass-engine/tools/sync_card_shader.py"),run_name="__main__")
