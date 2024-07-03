{ pkgs }: { name, src, defaultCompiler, shellOverrides ? { }, excludeCompilerMajors ? [ ] }:
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
          shell = if n == "default" then shell else { };
        }
      )
      compilers;
  checkFormat = pkgs.runCommandLocal "checkFormat"
    {
      inherit src;
      nativeBuildInputs = [ (projects.default.tool "fourmolu" shell.tools.fourmolu) pkgs.haskellPackages.cabal-fmt ];
    } ''
    cd $src
    fourmolu --mode check . >> $out
    cabal-fmt --check $(find . -type f -name "*.cabal") >> $out
  '';
  runFormat =
    pkgs.writeShellApplication {
      name = "formatHaskell.sh";
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
            paths = pkgs.lib.mapAttrsToList (_: package: package) projects.default.flake'.packages;
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
      program = "${runFormat}/bin/formatHaskell.sh";
    };
  };
  devShells = builtins.mapAttrs (_: project: project.flake'.devShells.default) projects;
  checks = projects.default.flake'.checks // {
    inherit checkFormat;
  };
}
