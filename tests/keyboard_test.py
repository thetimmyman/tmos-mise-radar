#!/usr/bin/python3
"""Drive the real panel from the keyboard in a fresh private shell.

The panel's key catcher is told what its keys would tell it (a move, Enter, Space) and the test
checks which button is highlighted and which action ran. The mise service is a recording double
and the stack service is the real one with no host configured, so no upgrade, ssh or browser
launch happens. Requires Omarchy/Quickshell and a running Wayland session: the panel is a layer-shell window,
though it is never opened. The private directory is removed on exit.
"""

import os
import shutil
import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
TIMEOUT_S = 25


def main():
    shell = Path("/usr/share/omarchy/shell")
    with tempfile.TemporaryDirectory(prefix="mise-radar-keyboard-test-") as directory:
        target = Path(directory)
        plugin = target / "plugin"
        plugin.mkdir()
        for name in ("Panel.qml", "StackService.qml", "Cursor.js"):
            shutil.copy2(ROOT / name, plugin / name)
        # Only the stack singleton: the panel is handed its services, it never imports the mise one.
        (plugin / "qmldir").write_text("singleton StackService 1.0 StackService.qml\n")
        shutil.copy2(ROOT / "tests/qml/keyboard_shell.qml", target / "shell.qml")
        for name in ("Ui", "Commons"):
            (target / name).symlink_to(shell / name, target_is_directory=True)
        try:
            done = subprocess.run(
                ["/usr/bin/qs", "-p", str(target), "--no-color"],
                stdin=subprocess.DEVNULL,
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                timeout=TIMEOUT_S,
                start_new_session=True,
                env=dict(os.environ),
            )
        except subprocess.TimeoutExpired as expired:
            print((expired.output or b"").decode("utf-8", "replace"), end="")
            raise SystemExit(
                f"keyboard QML test did not finish within {TIMEOUT_S}s"
            ) from None
        text = done.stdout.decode("utf-8", "replace")
        print(text, end="")
        if done.returncode or "FAIL " in text or "KEYBOARD_PANEL_OK" not in text:
            raise SystemExit(1)


if __name__ == "__main__":
    main()
