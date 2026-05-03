{
  description = "Roost macOS app package and nix-darwin module";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
  };

  outputs = { self, nixpkgs }:
    let
      supportedSystems = [ "aarch64-darwin" ];
      forAllSystems = nixpkgs.lib.genAttrs supportedSystems;
      pkgsFor = system: import nixpkgs { inherit system; };
    in
    {
      packages = forAllSystems (system:
        let
          pkgs = pkgsFor system;
        in
        {
          roost = pkgs.callPackage ./nix/package.nix { };
          default = self.packages.${system}.roost;
        });

      overlays.default = final: _prev: {
        roost =
          self.packages.${final.stdenv.hostPlatform.system}.roost
            or (throw "Roost currently provides a Nix package only for aarch64-darwin.");
      };

      darwinModules.default = import ./nix/darwin-module.nix { inherit self; };
      darwinModules.roost = self.darwinModules.default;
    };
}
