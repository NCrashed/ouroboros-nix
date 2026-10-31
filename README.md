# Ouroboros on NixOS

This flake wraps the official x86_64 AppImage release in a Nix FHS environment.
It also replaces the AppImage's old bundled Wayland client libraries inside the
runtime sandbox; without that compatibility fix, WebKit crashes against current
NixOS Mesa and the application shows a white window.
It provides:

- `ouroboros` — the headless CLI;
- `ouroboros-gui` — the desktop application;
- an `Ouroboros` entry in the desktop application menu.

The release is pinned to version 7.9.0 and verified with the SHA-256 digest
published in the GitHub release.

## Test without installing

```console
nix run .#smoke
nix run .#gui
```

The first build downloads the upstream AppImage (about 867 MB) and creates an
FHS runtime closure, so it is much larger than a typical Nix package.

## Install in the user profile

```console
nix profile install path:/home/user/dev/ouroboros-nix
ouroboros --help
ouroboros-gui
```

## Add to this host's NixOS flake

Add the input to `/etc/nixos/flake.nix`:

```nix
inputs.ouroboros = {
  url = "path:/home/user/dev/ouroboros-nix";
  inputs.nixpkgs.follows = "nixpkgs";
};
```

Add the module next to the existing modules:

```nix
modules = [
  ouroboros.nixosModules.default
  # existing modules...
];
```

Include `ouroboros` in the `outputs` argument set and enable it in
`configuration.nix`:

```nix
programs.ouroboros.enable = true;
```

Then rebuild in the normal way for this host.

## Runtime notes

- Ouroboros keeps its mutable repository, state, history, and logs under
  `~/Ouroboros`; these are intentionally outside the Nix store.
- The first CLI invocation performs the managed-repository bootstrap even for
  `ouroboros --help`. Expect `~/Ouroboros` to appear immediately; the bundled
  v7.9.0 seed occupies roughly 250 MB before any tasks or model downloads.
- The in-app updater changes that mutable repository and its Python packages,
  but not the AppImage's bundled CPython runtime. Update this flake when a new
  upstream desktop runtime is released.
- No systemd user unit is installed. Upstream documents its unit only for the
  native `.deb`/`.rpm` layout and recommends using one launch path per instance.
- The server listens on `127.0.0.1:8765` by default. Do not expose it on a
  non-loopback address without configuring Ouroboros authentication.
