#!/usr/bin/python3
"""Drive the real panel with real key and pointer events, offscreen.

QtTest sends key presses and mouse moves through a real window, so the shell's own key catcher,
action buttons, hover handling and tooltips all take part. Only the layer-shell window the panel
normally lives in cannot map without a compositor: a small stand-in with the same surface replaces
it. The mise service is a recording double and the stack service has no host configured, so no
upgrade, ssh or browser launch happens. No Wayland session is needed; the compositor-level pointer
and key-repeat flags are the part this cannot reproduce. The private directory, home included, is
removed on exit.
"""

import os
import shutil
import signal
import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
TIMEOUT_S = 90


def main():
    shell = Path("/usr/share/omarchy/shell")
    with tempfile.TemporaryDirectory(prefix="mise-radar-offscreen-test-") as directory:
        target = Path(directory)
        home = target / "home"
        home.mkdir()
        config = target / "config"
        config.mkdir()
        plugin = config / "plugin"
        plugin.mkdir()
        for name in ("Panel.qml", "StackService.qml", "Cursor.js"):
            shutil.copy2(ROOT / name, plugin / name)
        (plugin / "qmldir").write_text("singleton StackService 1.0 StackService.qml\n")
        shutil.copy2(ROOT / "tests/qml/offscreen_shell.qml", config / "shell.qml")
        # The shell's own Ui and Commons, except the layer-shell window the panel sits in.
        ui = config / "Ui"
        ui.mkdir()
        for entry in (shell / "Ui").iterdir():
            if entry.name == "KeyboardPanel.qml":
                shutil.copy2(ROOT / "tests/qml/offscreen/KeyboardPanel.qml", ui / entry.name)
            else:
                (ui / entry.name).symlink_to(entry)
        (config / "Commons").symlink_to(shell / "Commons", target_is_directory=True)
        env = {
            k: v
            for k, v in os.environ.items()
            if k not in ("WAYLAND_DISPLAY", "HYPRLAND_INSTANCE_SIGNATURE", "DISPLAY", "QT_QPA_PLATFORMTHEME")
        }
        env.update(QT_QPA_PLATFORM="offscreen", HOME=str(home))
        process = subprocess.Popen(
            ["/usr/bin/qs", "-p", str(config), "--no-color"],
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            start_new_session=True,
            env=env,
        )
        try:
            output, _ = process.communicate(timeout=TIMEOUT_S)
        except subprocess.TimeoutExpired:
            os.killpg(process.pid, signal.SIGKILL)
            output, _ = process.communicate()
            print(output.decode("utf-8", "replace"), end="")
            raise SystemExit(f"offscreen QML test did not finish within {TIMEOUT_S}s") from None
        text = output.decode("utf-8", "replace")
        print(text, end="")
        if process.returncode or "FAIL " in text or "OFFSCREEN_OK" not in text:
            raise SystemExit(1)


if __name__ == "__main__":
    main()
