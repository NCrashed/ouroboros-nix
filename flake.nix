{
  description = "NixOS wrapper for the Ouroboros desktop app and CLI";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

  outputs =
    { self, nixpkgs }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs { inherit system; };

      version = "7.9.0";
      pname = "ouroboros";
      src = pkgs.fetchurl {
        url = "https://github.com/razzant/ouroboros/releases/download/v${version}/Ouroboros-${version}-linux-x86_64.AppImage";
        hash = "sha256-tHO34jsZ2dQtmsiBu3kCp7FE/pnfpoDE48gSesSgCyk=";
      };
      appimageContents = pkgs.appimageTools.extract {
        inherit pname version src;
      };
      bundledGtkLibDir = "${appimageContents}/usr/lib/ouroboros/_internal/linux-gtk/lib/x86_64-linux-gnu";

      desktopItem = pkgs.makeDesktopItem {
        name = "ouroboros";
        desktopName = "Ouroboros";
        comment = "Self-creating AI agent with persistent identity";
        exec = "ouroboros-gui";
        icon = "ouroboros";
        categories = [
          "Development"
          "Utility"
        ];
        startupNotify = true;
        startupWMClass = "Ouroboros";
      };

      ouroboros = pkgs.appimageTools.wrapType2 {
        inherit pname version src;

        nativeBuildInputs = [ pkgs.makeWrapper ];

        # These are host tools used by Ouroboros itself. Supplying them inside
        # the FHS environment is more reliable than depending on the host PATH.
        extraPkgs = fhsPkgs: [
          fhsPkgs.cacert
          fhsPkgs.curl
          fhsPkgs.gh
          fhsPkgs.git
          fhsPkgs.git-lfs
          fhsPkgs.openssh
        ];

        # The AppImage was built on Ubuntu 22.04 and bundles Wayland 1.20.
        # Newer Mesa on NixOS requires a newer Wayland ABI; WebKit otherwise
        # aborts while creating its EGL display and leaves a white window.
        # Overlay only the conflicting libraries in the app's mount namespace
        # so LD_PRELOAD does not leak into Ouroboros workers and their tools.
        extraBwrapArgs = [
          "--ro-bind ${pkgs.wayland}/lib/libwayland-client.so.0 ${bundledGtkLibDir}/libwayland-client.so.0"
          "--ro-bind ${pkgs.wayland}/lib/libwayland-cursor.so.0 ${bundledGtkLibDir}/libwayland-cursor.so.0"
          "--ro-bind ${pkgs.wayland}/lib/libwayland-egl.so.1 ${bundledGtkLibDir}/libwayland-egl.so.1"
        ];

        desktopItems = [ desktopItem ];

        extraInstallCommands = ''
          install -Dm444 \
            ${appimageContents}/usr/share/icons/hicolor/1024x1024/apps/ouroboros.png \
            $out/share/icons/hicolor/1024x1024/apps/ouroboros.png

          # appimageTools initially creates $out/bin/ouroboros. Keep that
          # private, then expose the upstream GUI and CLI entry points as two
          # unambiguous commands.
          mv $out/bin/ouroboros $out/bin/.ouroboros-appimage
          makeWrapper $out/bin/.ouroboros-appimage $out/bin/ouroboros \
            --add-flags "--cli"
          makeWrapper $out/bin/.ouroboros-appimage $out/bin/ouroboros-gui
        '';

        meta = {
          description = "General-purpose AI agent with durable memory and a desktop or headless interface";
          homepage = "https://github.com/razzant/ouroboros";
          license = pkgs.lib.licenses.mit;
          mainProgram = "ouroboros";
          platforms = [ "x86_64-linux" ];
          sourceProvenance = [ pkgs.lib.sourceTypes.binaryNativeCode ];
        };
      };

      smoke = pkgs.writeShellApplication {
        name = "ouroboros-smoke";
        runtimeInputs = [ pkgs.gnugrep ];
        text = ''
          smoke_root="$(mktemp -d -t ouroboros-smoke.XXXXXXXX)"
          cleanup() {
            case "$smoke_root" in
              /tmp/ouroboros-smoke.*) rm -rf -- "$smoke_root" ;;
              *) echo "Refusing to clean unexpected smoke path: $smoke_root" >&2 ;;
            esac
          }
          trap cleanup EXIT

          export HOME="$smoke_root/home"
          export XDG_CACHE_HOME="$smoke_root/cache"
          export XDG_CONFIG_HOME="$smoke_root/config"
          export XDG_DATA_HOME="$smoke_root/data"
          export XDG_STATE_HOME="$smoke_root/state"
          mkdir -p "$HOME"

          version_output="$(${ouroboros}/bin/ouroboros-gui --version)"
          grep -Fx "Ouroboros ${version}" <<<"$version_output"
          ${ouroboros}/bin/ouroboros --help >/dev/null
          echo "Ouroboros ${version}: GUI entry point and CLI help are available"
        '';
      };
    in
    {
      packages.${system} = {
        default = ouroboros;
        inherit ouroboros;
      };

      apps.${system} = {
        default = {
          type = "app";
          program = "${ouroboros}/bin/ouroboros";
          meta.description = "Run the Ouroboros CLI";
        };
        gui = {
          type = "app";
          program = "${ouroboros}/bin/ouroboros-gui";
          meta.description = "Run the Ouroboros desktop application";
        };
        smoke = {
          type = "app";
          program = "${smoke}/bin/ouroboros-smoke";
          meta.description = "Verify the packaged Ouroboros GUI and CLI entry points";
        };
      };

      nixosModules.default =
        { config, lib, pkgs, ... }:
        let
          cfg = config.programs.ouroboros;
        in
        {
          options.programs.ouroboros = {
            enable = lib.mkEnableOption "the Ouroboros desktop app and CLI";
            package = lib.mkOption {
              type = lib.types.package;
              default = self.packages.${pkgs.stdenv.hostPlatform.system}.default;
              defaultText = lib.literalExpression "ouroboros.packages.${pkgs.stdenv.hostPlatform.system}.default";
              description = "Ouroboros package to install.";
            };
          };

          config = lib.mkIf cfg.enable {
            environment.systemPackages = [ cfg.package ];
          };
        };
    };
}
