{
  description = "Personal tools for managing and developing a Haskell project with nix flakes";

  inputs = {
    haskellNix.url = "github:input-output-hk/haskell.nix";
    nixpkgs.follows = "haskellNix/nixpkgs-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, haskellNix, flake-utils }:
    flake-utils.lib.eachDefaultSystem
      (system:
        let
          overlay = final: pkgs: {
            haskell-project-flake = pkgs.callPackage ./default.nix { };
          };
        in
        rec {
          overlays.default = (import nixpkgs { inherit system; }).lib.fixedPoints.composeExtensions
            haskellNix.overlay
            overlay;
          legacyPackages = import nixpkgs {
            inherit system;
            inherit (haskellNix) config;
            overlays = [ overlays.default ];
          };
        }
      ) // rec {
      templates.haskell-project-flake = {
        path = ./templates/haskell-project-flake;
        description = "Set up haskell project infrastructure";
      };
      templates.default = templates.haskell-project-flake;
    }
  ;
}
