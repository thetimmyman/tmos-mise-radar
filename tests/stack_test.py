#!/usr/bin/python3
"""Exercise the real StackService in a fresh private shell.

The ssh paths are covered by the popup test's fake service; what is checked here is the part that
decides which row a click is aimed at, when a second click is armed, and how a failed check is
described. No consumer is acquired and no target is configured, so this run starts no process and
needs no host, key or network.

Requires Omarchy/Quickshell. The private directory is removed on exit.
"""
import os
import shutil
import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
TIMEOUT_S = 20


def main():
    shell = Path('/usr/share/omarchy/shell')
    with tempfile.TemporaryDirectory(prefix='mise-radar-stack-test-') as directory:
        target = Path(directory)
        plugin = target / 'plugin'
        plugin.mkdir()
        for name in ('StackService.qml',):
            shutil.copy2(ROOT / name, plugin / name)
        # Only the singleton under test: importing the whole module would load the mise service too.
        (plugin / 'qmldir').write_text('singleton StackService 1.0 StackService.qml\n')
        shutil.copy2(ROOT / 'tests/qml/stack_shell.qml', target / 'shell.qml')
        for name in ('Ui', 'Commons'):
            (target / name).symlink_to(shell / name, target_is_directory=True)
        try:
            done = subprocess.run(['/usr/bin/qs', '-p', str(target), '--no-color'],
                                  stdin=subprocess.DEVNULL, stdout=subprocess.PIPE,
                                  stderr=subprocess.STDOUT, timeout=TIMEOUT_S,
                                  start_new_session=True,
                                  env=dict(os.environ, QT_QPA_PLATFORM='offscreen'))
        except subprocess.TimeoutExpired as expired:
            print((expired.output or b'').decode('utf-8', 'replace'), end='')
            raise SystemExit(f'stack QML test did not finish within {TIMEOUT_S}s') from None
        text = done.stdout.decode('utf-8', 'replace')
        print(text, end='')
        if done.returncode or 'FAIL ' in text or 'STACK_RUNTIME_OK' not in text:
            raise SystemExit(1)


if __name__ == '__main__':
    main()
