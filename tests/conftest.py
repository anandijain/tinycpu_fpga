import os
import shutil
from pathlib import Path

import pytest


@pytest.fixture(autouse=True)
def use_project_python_in_icarus(monkeypatch):
    vvp = shutil.which("vvp")
    if vvp is None:
        return
    suite = Path(vvp).resolve().parents[1]
    loader = suite / "lib/ld-linux-x86-64.so.2"
    if loader.is_file() and (suite / "libexec/vvp").is_file():
        monkeypatch.setenv("COCOTB_OSS_CAD_ROOT", str(suite))
        monkeypatch.setenv(
            "PATH", str(Path(__file__).with_name("bin")), prepend=os.pathsep
        )
