{
  description = "Personal tools for managing and developing a Haskell project with nix flakes";

  inputs = {
    haskellNix.url = "github:input-output-hk/haskell.nix";
    nixpkgs.follows = "haskellNix/nixpkgs-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, haskellNix, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        overlay = final: pkgs: {
          haskell-project-flake = { name, src, defaultCompiler, shellOverrides ? { }, excludeCompilerMajors ? [ ] }:
            let
              compilers = pkgs.lib.attrsets.filterAttrs (n: _: !(pkgs.lib.strings.hasSuffix "llvm" n) && !(builtins.elem n excludeCompilerMajors))
                pkgs.haskell-nix.compilerNameMap // { default = defaultCompiler; };
              shell =
                pkgs.lib.attrsets.recursiveUpdate
                  {
                    withHoogle = false;
                    tools = {
                      cabal = { };
                      hlint = { };
                      haskell-language-server = { };
                      fourmolu = { };
                    };
                  }
                  shellOverrides;
              projects =
                builtins.mapAttrs
                  (n: c:
                    pkgs.haskell-nix.project' {
                      inherit name src;
                      compiler-nix-name = c;
                      shell = if n == "default" then shell else
                      shell // {
                        tools = builtins.intersectAttrs { cabal = { }; } shell.tools;
                      };
                    }
                  )
                  compilers;
              checkFormat = pkgs.runCommandLocal "checkFormat"
                {
                  inherit src;
                  nativeBuildInputs = [ projects.default.tool "fourmolu" shell.tools.fourmolu ];
                } "fourmolu --mode check $src > $out";
              runFormat =
                pkgs.writeShellApplication {
                  name = "formatHaskell.sh";
                  runtimeInputs = [ projects.default.tool "fourmolu" shell.tools.fourmolu ];
                  text = ''
                    # shellcheck disable=SC2046
                    fourmolu --mode inplace $(git ls-files '*.hs')
                  '';
                };
              packagesByCompiler =
                builtins.mapAttrs
                  (v: project:
                    project.flake'.packages
                    // {
                      all = pkgs.symlinkJoin {
                        name = "${name}-${v}";
                        paths = pkgs.lib.mapAttrsToList (_: package: package) projects.default.flake'.packages;
                      };
                    }
                  )
                  projects;
            in
            rec {
              inherit projects;
              packages = packagesByCompiler.default // { default = packages.default.all; withCompiler = packages; };
              apps = {
                format = {
                  type = "app";
                  program = "${runFormat}/bin/formatHaskell.sh";
                };
              };
              devShells = builtins.mapAttrs (_: project: project.flake'.devShells.default) projects;
              checks = projects.default.flake'.checks // {
                inherit checkFormat;
              };
            };
        };
      in
      rec {
        overlays.default = (import nixpkgs { inherit system; }).lib.fixedPoints.composeExtensions haskellNix.overlay overlay;
        legacyPackages = import nixpkgs {
          inherit system;
          inherit (haskellNix) config;
          overlays = [ overlays.default ];
        };
      }
    );
}
