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
          pkgs = import nixpkgs {
            inherit system;
            config.allowUnfree = true;
          };
          binary = {
            "x86_64-linux" = {
              version = "4.4.0";
              systemName = "linux";
              arch = "";
              hash = "sha256-jToCykYMdCWbo8/xec6WFAXfUTYDVgQph/hTQJ/Hii4=";
            };
            "x86_64-darwin" = {
              version = "4.4.0";
              systemName = "darwin";
              arch = "";
              hash = "sha256-IdTSHX9O/SmU+WZJknrboEtY4WfCP9BbCwQHQxTkh9I=";
            };
          }.${system};
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
              [ ] ++
              lib.optional stdenv.hostPlatform.isDarwin fixDarwinDylibNames;
            src = pkgs.fetchzip {
              url = "https://github.com/leanprover/lean4/releases/download/v${binary.version}/lean-${binary.version}-${binary.systemName}${binary.arch}.zip";
              hash = binary.hash;
            };
            dontBuild = true;
            installPhase = with pkgs; ''
              mkdir -p $out
              rsync -a . $out/
            '';
            doDist = true;
            distPhase = with pkgs;
              lib.strings.optionalString stdenv.hostPlatform.isDarwin ''
                for exe in $(find $out -type f -exec file {} \; | grep Mach-O \
                  | cut -d: -f1 | grep -v '\.a$'); do 
                  install_name_tool \
                    -change "@rpath/libc++abi.1.dylib" "${libcxxabi}/lib/libc++abi.1.dylib" \
                    -change "@rpath/libunwind.1.dylib" "${llvmPackages_15.libunwind}/lib/libunwind.1.dylib" \
                    $exe
                done
                echo "install_name_tool done in Darwin"
              '' +
              lib.strings.optionalString stdenv.hostPlatform.isLinux ''
                find $out/bin -type f -exec file {} \; | grep ELF \
                  | cut -d: -f1 | grep -v '\.o$' \
                  | xargs patchelf --set-rpath \
                  "${stdenv.cc.cc.lib}/lib:${glibc}/lib:${libcxx}/lib:${libcxxabi}/lib:${llvmPackages_15.libllvm.lib}/lib:${llvmPackages_15.libunwind}/lib:${llvmPackages_15.clang-unwrapped.lib}/lib:"'$ORIGIN/../lib:$ORIGIN/../lib/lean'
                patchelf \
                  --set-rpath "${stdenv.cc.cc.lib}/lib:${glibc}/lib:${libcxx}/lib:"'$ORIGIN/..:$ORIGIN' \
                  $out/lib/lean/libleanshared.so
                find $out/bin -type f -exec file {} \; | grep ELF \
                  | cut -d: -f1 \
                  | xargs patchelf --set-interpreter "${stdenv.cc.bintools.dynamicLinker}"
                echo "Patchelf done in Linux"
                ln -sf ${llvmPackages_15.libllvm}/bin/llvm-ar $out/bin
                ln -sf ${clang_15}/bin/clang $out/bin
                ln -sf ${lld_15}/bin/ld.lld $out/bin
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
