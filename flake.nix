{
  description = "Tiny event-driven fullscreen auto-hide for Noctalia on Niri";
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  outputs = { self, nixpkgs }: let
    systems = [ "x86_64-linux" "aarch64-linux" ];
    eachSystem = nixpkgs.lib.genAttrs systems;
  in {
    homeManagerModules.default = import ./nix/home-manager.nix self;
    packages = eachSystem (system: let pkgs = import nixpkgs { inherit system; }; in {
      default = pkgs.callPackage ./package.nix { };
    });
    devShells = eachSystem (system: let pkgs = import nixpkgs { inherit system; }; in {
      default = pkgs.mkShell { packages = [ pkgs.zig_0_15 ]; };
    });
  };
}
