{ self }:
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.programs.roost;
  system = pkgs.stdenv.hostPlatform.system;
  defaultPackage =
    self.packages.${system}.roost
      or (throw "Roost currently provides a Nix package only for aarch64-darwin.");
in
{
  options.programs.roost = {
    enable = lib.mkEnableOption "Roost";

    package = lib.mkOption {
      type = lib.types.package;
      default = defaultPackage;
      defaultText = lib.literalExpression "inputs.roost.packages.${pkgs.stdenv.hostPlatform.system}.roost";
      description = "Roost package to install.";
    };

    linkApplication = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Whether to link Roost.app into the configured macOS applications directory during activation.";
    };

    applicationDirectory = lib.mkOption {
      type = lib.types.str;
      default = "/Applications/Nix Apps";
      description = "Directory where the Roost.app activation symlink is placed.";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [ cfg.package ];

    system.activationScripts.roostApplicationAlias.text = lib.mkIf cfg.linkApplication ''
      app_dir=${lib.escapeShellArg cfg.applicationDirectory}
      /usr/bin/install -d -m 0755 "$app_dir"
      /bin/rm -f "$app_dir/Roost.app"
      /bin/ln -s "${cfg.package}/Applications/Roost.app" "$app_dir/Roost.app"
    '';
  };
}
