#!/usr/bin/env python3
"""Exercise the real binary against a fake Niri socket and Noctalia executable."""
import json
import os
from pathlib import Path
import signal
import socket
import subprocess
import sys
import tempfile
import threading
import time

binary = str(Path(sys.argv[1] if len(sys.argv) > 1 else "zig-out/bin/noctalia-fullscreen").resolve())
with tempfile.TemporaryDirectory() as tmp:
    root = Path(tmp)
    log = root / "commands"
    cli = root / "noctalia"
    cli.write_text('#!/bin/sh\nprintf "%s\\n" "$*" >> "$COMMAND_LOG"\n')
    cli.chmod(0o755)
    server = socket.socket(socket.AF_UNIX)
    server.bind(str(root / "niri.sock"))
    server.listen()
    stream = []
    connected = threading.Event()

    def serve():
        while True:
            connection, _ = server.accept()
            request = connection.makefile("rb").readline()
            if json.loads(request) == "Outputs":
                response = {"Ok": {"Outputs": {"DP-1": {"logical": {"width": 1920, "height": 1080}}}}}
                connection.sendall(json.dumps(response).encode() + b"\n")
                connection.close()
            else:
                connection.sendall(b'{"Ok":"Handled"}\n')
                stream.append(connection)
                connected.set()

    threading.Thread(target=serve, daemon=True).start()
    env = dict(os.environ, NIRI_SOCKET=str(root / "niri.sock"), COMMAND_LOG=str(log))
    process = subprocess.Popen([binary, "--noctalia", str(cli)], env=env,
                               stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)

    def wait_for(predicate):
        deadline = time.monotonic() + 4
        while not predicate():
            if process.poll() is not None:
                raise AssertionError(process.stderr.read().decode())
            if time.monotonic() > deadline:
                raise AssertionError("Timed out waiting for commands")
            time.sleep(0.01)

    def lines():
        return log.read_text().splitlines() if log.exists() else []

    def event(value):
        stream[0].sendall(json.dumps(value).encode() + b"\n")

    try:
        assert connected.wait(4)
        event({"WorkspacesChanged": {"workspaces": [
            {"id": 1, "output": "DP-1", "is_active": True, "active_window_id": 7}]}})
        event({"WindowsChanged": {"windows": [
            {"id": 7, "workspace_id": 1, "layout": {"tile_size": [1920, 1047]}}]}})
        wait_for(lambda: len(lines()) >= 2)
        assert lines()[-2:] == ["msg bar-layer-set top main DP-1", "msg bar-auto-hide-set off main DP-1"]
        event({"WindowLayoutsChanged": {"changes": [[7, {"tile_size": [1920, 1080]}]]}})
        wait_for(lambda: "msg bar-layer-set overlay main DP-1" in lines())
        assert lines()[-2:] == ["msg bar-auto-hide-set smart main DP-1", "msg bar-layer-set overlay main DP-1"]
        count = len(lines())
        event({"WindowFocusChanged": {"id": 7}})
        # A fence layout event is processed without sending redundant bar commands.
        event({"WindowLayoutsChanged": {"changes": [[7, {"tile_size": [1920, 1080]}]]}})
        time.sleep(0.1)
        assert len(lines()) == count
        process.send_signal(signal.SIGHUP)
        wait_for(lambda: len(lines()) >= count + 2)
        assert lines()[-2:] == ["msg bar-auto-hide-set smart main DP-1", "msg bar-layer-set overlay main DP-1"]
        process.send_signal(signal.SIGTERM)
        assert process.wait(timeout=4) == 0
        assert lines()[-2:] == ["msg bar-layer-set top main DP-1", "msg bar-auto-hide-set off main DP-1"]
        print("PASS: socket events, command ordering, deduplication, SIGHUP resync, SIGTERM restore")
    finally:
        if process.poll() is None:
            process.kill()
            process.wait()
        for connection in stream:
            connection.close()
        server.close()
