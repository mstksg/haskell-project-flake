{ pkgs }: { name, src, defaultCompiler, shellOverrides ? { }, excludeCompilerMajors ? [ ] }:
let
  compilers = pkgs.lib.attrsets.filterAttrs (n: _: !(pkgs.lib.strings.hasSuffix "llvm" n) && !(builtins.elem n excludeCompilerMajors))
    pkgs.haskell-nix.compilerNameMap // { default = defaultCompiler; };
  shell =
    pkgs.lib.attrsets.recursiveUpdate
      {
        tools = {
          cabal = { };
          hlint = { };
          haskell-language-server = { };
          fourmolu = { };
        };
      }
      shellOverrides;
  bareShell =
    pkgs.lib.attrsets.recursiveUpdate
      {
        tools = { cabal = { }; };
      }
      shellOverrides;
  projects =
    builtins.mapAttrs
      (n: c:
        pkgs.haskell-nix.project' {
          inherit name src;
          compiler-nix-name = c;
          # TODO: find a way to get the correct cabal
          shell = if n == "default" then shell else { };
        }
      )
      compilers;
  checkFormat = pkgs.runCommandLocal "checkHaskell"
    {
      inherit src;
      nativeBuildInputs =
        let tools = projects.default.tools { hlint = { }; fourmolu = { }; };
        in [ tools.fourmolu tools.hlint pkgs.haskellPackages.cabal-fmt ];
    } ''
    cd $src
    fourmolu --mode check .
    cabal-fmt --check $(find . -type f -name "*.cabal")
    hlint .
    touch $out
  '';
  runCheck =
    pkgs.writeShellApplication {
      name = "check-haskell";
      runtimeInputs =
        let tools = projects.default.tools { hlint = { }; fourmolu = { }; };
        in [ tools.fourmolu tools.hlint pkgs.haskellPackages.cabal-fmt ];
      text = ''
        # shellcheck disable=SC2046
        fourmolu --mode check $(git ls-files '*.hs')
        # shellcheck disable=SC2046
        cabal-fmt --check $(git ls-files '*.cabal')
        # shellcheck disable=SC2046
        hlint $(git ls-files '*.hs')
      '';
    };
  runFormat =
    pkgs.writeShellApplication {
      name = "format-haskell";
      runtimeInputs = [ (projects.default.tool "fourmolu" shell.tools.fourmolu) ];
      text = ''
        # shellcheck disable=SC2046
        fourmolu --mode inplace $(git ls-files '*.hs')
        # shellcheck disable=SC2046
        cabal-fmt --inplace $(git ls-files '*.cabal')
      '';
    };
  packagesByCompiler =
    builtins.mapAttrs
      (v: project:
        project.flake'.packages
        // {
          all = pkgs.symlinkJoin {
            name = "${name}-${v}";
            paths = pkgs.lib.mapAttrsToList (_: package: package)
              project.flake'.packages
            ++ pkgs.lib.mapAttrsToList (_: check: check) project.flake'.checks;
          };
        }
      )
      projects;
in
rec {
  inherit projects packagesByCompiler;
  packages = builtins.mapAttrs (_: p: p.all) packagesByCompiler // {
    default =
      packagesByCompiler.default.all;
    everyCompiler = pkgs.symlinkJoin {
      name = "${name}-every-compiler";
      paths = pkgs.lib.mapAttrsToList (_: package: package.all) packagesByCompiler;
    };
  };
  # TODO: add actions for making a release (parsing changelog?) and pushing to
  # hackage
  apps = {
    format = {
      type = "app";
      program = "${runFormat}/bin/format-haskell.sh";
    };
  };
  devShells = builtins.mapAttrs
    (v: project: project.shellFor (
      if v == "default" then shell // {
        buildInputs = [ runFormat runCheck ];
      } else bareShell
    ))
    projects;
  checks = projects.default.flake'.checks // {
    inherit checkFormat;
  };
}
