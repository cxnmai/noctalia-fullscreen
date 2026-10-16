# noctalia-fullscreen

Tiny, event-driven **Zig** helper for fullscreen-only Noctalia bar auto-hide on **Niri**.

| Visible active window on a monitor | Existing Noctalia behavior |
| --- | --- |
| Normal, maximized, or windowed fullscreen | **Off**, Top layer |
| Real fullscreen | **Smart**, Overlay layer — move the pointer to the bar edge to reveal it |

No reimplementation of auto-hide. No polling, shell loop, Python runtime, or persistent
`niri msg` subprocess. One native process sleeps on the Niri IPC socket and a signal
eventfd, invoking `noctalia msg` only when a monitor's desired mode changes.

## Requirements and detection

- Linux, Niri with `WindowLayoutsChanged` IPC events (tested on **26.04**).
- Noctalia with `bar-auto-hide-set` and `bar-layer-set` IPC (tested on **5.2.0**).
- The controlled bar must have **`reserve_space = true`** and nonzero thickness.
- Only one helper should control a given bar. The helper owns that bar's runtime
  auto-hide/layer settings; stopping it restores **Off / Top**.

Niri does not expose a real-fullscreen boolean in its window IPC. Its Wayland
fullscreen flag also includes fake/windowed fullscreen and does not identify visible
workspaces. Instead, this helper compares the **active window's tile size** with the
output's logical size, independently on each output's **active workspace**.

With reserved bar space, normal/maximized/windowed-fullscreen tiles are smaller than
the monitor. Real fullscreen includes the whole monitor (and any backdrop for a
fixed-size client). This also works when another monitor has keyboard focus. Hidden
workspaces and inactive columns do not activate auto-hide.

**This is a geometry-based inference, not a compositor fullscreen-state API.** An
artificially sized non-fullscreen window matching the monitor exactly can be a false
positive. Removing the bar's reserved space, unsupported IPC changes, or unusual
compositor sizing rules can invalidate the inference. Do not use it without the
reserved-space requirement. Fractional scaling uses logical, not physical, dimensions.

## Build and run

Requires **Zig 0.15.2**, libc, and no other libraries or fetched Zig dependencies:

```sh
zig build -Doptimize=ReleaseSmall
./zig-out/bin/noctalia-fullscreen --dry-run
./zig-out/bin/noctalia-fullscreen
```

Or use the pinned Nix toolchain:

```sh
nix develop -c zig build -Doptimize=ReleaseSmall
nix run . -- --dry-run
nix build
```

Options: `--bar NAME` (default `main`), `--noctalia PATH` (default `noctalia`
from PATH), `--dry-run`, `--reset`, `--help`, and `--version`.
`NIRI_SOCKET` must be set by the Niri session. Monitor connector names are discovered;
no machine-specific configuration is baked in.

SIGINT/SIGTERM restore Off / Top and exit. SIGHUP invalidates cached settings and
reapplies the current state. IPC/command failures exit nonzero, allowing systemd to
restart the helper. Noctalia commands use argument arrays, never shell interpolation.

## Home Manager

Add a flake input:

```nix
inputs.noctalia-fullscreen = {
  url = "github:cxnmai/noctalia-fullscreen";
  inputs.nixpkgs.follows = "nixpkgs";
};
```

Then in your Home Manager configuration (with `inputs` passed as an extra argument):

```nix
{ inputs, ... }: {
  imports = [ inputs.noctalia-fullscreen.homeManagerModules.default ];
  services.noctalia-fullscreen.enable = true;
  programs.noctalia.settings.bar.main.reserve_space = true;
}
```

The module expects the existing `noctalia.service`, starts/stops the helper with it,
and restarts it when Noctalia restarts. Optional settings: `bar`, `package`, and
`noctaliaPackage`. If the shell was already running when you enabled the module:

```sh
systemctl --user start noctalia-fullscreen
```

**Noctalia config reloads reset its transient overrides.** After an in-process config
reload or editing its settings UI, run `systemctl --user reload noctalia-fullscreen`
(or send SIGHUP to a manually launched helper). The helper cannot observe a silent
Noctalia-only config reload through Niri's IPC. Normal service restarts are handled
automatically by the module. No periodic reapplication is used.

To disable: `systemctl --user stop noctalia-fullscreen`. To recover after SIGKILL:
`noctalia-fullscreen --reset`. A directly launched helper must be restarted after
Noctalia restarts; use the service for normal operation.

## Tests

```sh
zig build test
python3 tests/integration.py # build the executable first
```

Unit tests cover independent monitors, hidden workspaces, inactive columns, fullscreen
entry/exit, fixed-size clients, output changes, and unknown events. The integration
test uses a fake Unix socket/Noctalia executable to check real command dispatch,
deduplication, resynchronization, and shutdown restoration without touching a desktop.

MIT licensed.
