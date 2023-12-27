{
  description = "Lean 4";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs";
    flake-utils.url = "github:numtide/flake-utils";
    shell-utils.url = "github:waltermoreira/shell-utils";
    myvscode.url = "github:waltermoreira/myvscode";
  };

  outputs = { self, nixpkgs, flake-utils, shell-utils, myvscode }:
    with flake-utils.lib; eachSystem [
      system.x86_64-linux
      system.x86_64-darwin
    ]
      (system:
        let
          leanVersion = "4.4.0";
          elanVersion = "3.0.0";
          pkgs = import nixpkgs {
            inherit system;
            config.allowUnfree = true;
          };
          binary = {
            "x86_64-linux" = {
              version = leanVersion;
              systemName = "linux";
              arch = "";
              hash = "sha256-jToCykYMdCWbo8/xec6WFAXfUTYDVgQph/hTQJ/Hii4=";
            };
            "x86_64-darwin" = {
              version = leanVersion;
              systemName = "darwin";
              arch = "";
              hash = "sha256-IdTSHX9O/SmU+WZJknrboEtY4WfCP9BbCwQHQxTkh9I=";
            };
          }.${system};
          elan_binary = {
            "x86_64-linux" = {
              version = elanVersion;
              systemName = "unknown-linux-gnu";
              arch = "x86_64";
              hash = "sha256-p4KPgU0tJTo2fQdXwCZqviQQflsd432FnCu2pzekWfc=";
            };
            "x86_64-darwin" = {
              version = elanVersion;
              systemName = "apple-darwin";
              arch = "x86_64";
              hash = "";
            };
          }.${system};
          toolchain = "leanprover--lean4---v${binary.version}";
          toolchainsPath = "bin/toolchains/${toolchain}";
          elan = pkgs.stdenv.mkDerivation {
            name = "elan";
            src = pkgs.fetchzip {
              url = "https://github.com/leanprover/elan/releases/download/v${elan_binary.version}/elan-${elan_binary.arch}-${elan_binary.systemName}.tar.gz";
              hash = elan_binary.hash;
            };
            installPhase = with pkgs; ''
              mkdir -p $out/bin
              cp elan-init $out/bin/elan
            '';
          };
          lean4 = pkgs.stdenv.mkDerivation {
            name = "lean4";
            buildInputs = with pkgs; [
              rsync
              findutils
              file
            ] ++ lib.lists.optionals stdenv.hostPlatform.isLinux [
              stdenv.cc.cc.lib
            ];
            nativeBuildInputs = with pkgs;
              [ makeWrapper ] ++
              lib.optional stdenv.hostPlatform.isDarwin fixDarwinDylibNames;
            src = pkgs.fetchzip {
              url = "https://github.com/leanprover/lean4/releases/download/v${binary.version}/lean-${binary.version}-${binary.systemName}${binary.arch}.zip";
              hash = binary.hash;
            };
            dontBuild = true;
            installPhase = with pkgs; ''
              mkdir -p $out/${toolchainsPath}
              mkdir -p $out/{bin/update-hashes,_unwrapped}
              rsync -a . $out/${toolchainsPath}
            '';
            doDist = true;
            distPhase = with pkgs;
              lib.strings.optionalString stdenv.hostPlatform.isDarwin ''
                for exe in $(find $out/${toolchainsPath} -type f -exec file {} \; | grep Mach-O \
                  | cut -d: -f1 | grep -v '\.a$'); do 
                  install_name_tool \
                    -change "@rpath/libc++abi.1.dylib" "${libcxxabi}/lib/libc++abi.1.dylib" \
                    -change "@rpath/libunwind.1.dylib" "${llvmPackages_15.libunwind}/lib/libunwind.1.dylib" \
                    $exe
                done
                echo "install_name_tool done in Darwin"
              '' +
              lib.strings.optionalString stdenv.hostPlatform.isLinux ''
                find $out/${toolchainsPath}/bin -type f -exec file {} \; | grep ELF \
                  | cut -d: -f1 | grep -v '\.o$' \
                  | xargs patchelf --set-rpath \
                  "${stdenv.cc.cc.lib}/lib:${glibc}/lib:${libcxx}/lib:${libcxxabi}/lib:${llvmPackages_15.libllvm.lib}/lib:${llvmPackages_15.libunwind}/lib:${llvmPackages_15.clang-unwrapped.lib}/lib:"'$ORIGIN/../lib:$ORIGIN/../lib/lean'
                patchelf \
                  --set-rpath "${stdenv.cc.cc.lib}/lib:${glibc}/lib:${libcxx}/lib:"'$ORIGIN/..:$ORIGIN' \
                  $out/${toolchainsPath}/lib/lean/libleanshared.so
                find $out/${toolchainsPath}/bin -type f -exec file {} \; | grep ELF \
                  | cut -d: -f1 \
                  | xargs patchelf --set-interpreter "${stdenv.cc.bintools.dynamicLinker}"
                echo "Patchelf done in Linux"
                ln -sf ${llvmPackages_15.libllvm}/bin/llvm-ar $out/${toolchainsPath}/bin
                ln -sf ${llvmPackages_15.clangUseLLVM}/bin/clang $out/${toolchainsPath}/bin
                ln -sf ${llvmPackages_15.bintools}/bin/ld.lld $out/${toolchainsPath}/bin
              '' + ''
                for binary in elan lake lean leanc leanchecker leanmake leanpkg; do
                  cp ${elan}/bin/elan $out/_unwrapped/$binary
                  makeWrapper $out/_unwrapped/$binary $out/bin/$binary \
                    --set-default ELAN_HOME $out/bin \
                    --prefix PATH : $out/${toolchainsPath}/bin \
                    --prefix PATH : $out/bin
                done
                echo -n "https://github.com/leanprover/lean4/releases/expanded_assets/v${binary.version}" >$out/bin/update-hashes/${toolchain}
                cat <<EOF >$out/bin/settings.toml
                default_toolchain = "${toolchain}"
                telemetry = false
                version = "12"

                [overrides]
                EOF
              '';
          };
          vscode-lean4 = pkgs.vscode-utils.extensionFromVscodeMarketplace {
            name = "lean4";
            publisher = "leanprover";
            version = "0.0.103";
            sha256 = "sha256-3hpvln4IW53ApMm2PFr2v8Gd5ZdSSzc0cAz1hvS6jWU=";
          };
          myShell = shell-utils.myShell.${system};
          vscode = myvscode.makeMyVSCode pkgs {
            extraExtensions = [
              vscode-lean4
            ];
            extraSettings = {
              "lean4.toolchainPath" = "${lean4}";
            };
          };
        in
        {
          packages.default = lean4;
          devShells.default = myShell {
            packages = [
              lean4
              vscode
            ];
          };
        });
}
