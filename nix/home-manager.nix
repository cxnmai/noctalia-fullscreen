self: { config, lib, pkgs, ... }:
let
  cfg = config.services.noctalia-fullscreen;
in {
  options.services.noctalia-fullscreen = {
    enable = lib.mkEnableOption "event-driven Noctalia fullscreen auto-hide on Niri";
    package = lib.mkOption {
      type = lib.types.package;
      default = self.packages.${pkgs.stdenv.hostPlatform.system}.default;
      description = "The noctalia-fullscreen package.";
    };
    noctaliaPackage = lib.mkOption {
      type = lib.types.package;
      default = pkgs.noctalia;
      description = "Noctalia package whose IPC client should be used.";
    };
    bar = lib.mkOption {
      type = lib.types.str;
      default = "main";
      description = "Name of the Noctalia bar to control on each monitor.";
    };
  };
  config = lib.mkIf cfg.enable {
    home.packages = [ cfg.package ];
    systemd.user.services.noctalia-fullscreen = {
      Unit = {
        Description = "Fullscreen-only auto-hide for the Noctalia bar";
        After = [ "noctalia.service" ];
        BindsTo = [ "noctalia.service" ];
        PartOf = [ "graphical-session.target" "noctalia.service" ];
        StartLimitIntervalSec = 30;
        StartLimitBurst = 5;
      };
      Service = {
        ExecStart = lib.escapeShellArgs [
          "${cfg.package}/bin/noctalia-fullscreen"
          "--noctalia" "${cfg.noctaliaPackage}/bin/noctalia"
          "--bar" cfg.bar
        ];
        Environment = "LD_LIBRARY_PATH=";
        ExecReload = "${pkgs.coreutils}/bin/kill -HUP $MAINPID";
        Restart = "on-failure";
        RestartSec = 2;
        TimeoutStopSec = 10;
      };
      Install.WantedBy = [ "noctalia.service" ];
    };
  };
}
