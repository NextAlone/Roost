# Roost with nix-darwin

Roost exposes a small flake for Apple Silicon Macs. It packages the published self-signed ZIP release and provides a `nix-darwin` module that can be imported directly.

## Flake Input

Add Roost to your `nix-darwin` flake inputs:

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    nix-darwin.url = "github:nix-darwin/nix-darwin/master";
    nix-darwin.inputs.nixpkgs.follows = "nixpkgs";

    roost.url = "github:NextAlone/Roost/v1.1.0";
    roost.inputs.nixpkgs.follows = "nixpkgs";
  };
}
```

## Module Usage

Import the module and enable Roost:

```nix
{
  inputs,
  ...
}: {
  darwinConfigurations."Your-Mac" = inputs.nix-darwin.lib.darwinSystem {
    system = "aarch64-darwin";
    modules = [
      inputs.roost.darwinModules.default
      {
        programs.roost.enable = true;
      }
    ];
  };
}
```

The module adds Roost to `environment.systemPackages` and links the app to `/Applications/Nix Apps/Roost.app` during activation.

## Package-Only Usage

If you do not want the module, install the package directly:

```nix
{
  inputs,
  pkgs,
  ...
}: {
  environment.systemPackages = [
    inputs.roost.packages.${pkgs.stdenv.hostPlatform.system}.default
  ];
}
```

## Options

```nix
{
  programs.roost = {
    enable = true;
    linkApplication = true;
    applicationDirectory = "/Applications/Nix Apps";
  };
}
```

Roost currently ships only an `aarch64-darwin` package. The package follows the current release model: self-signed/ad-hoc, non-notarized, and manually published through GitHub Releases.
