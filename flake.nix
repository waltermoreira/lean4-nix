{
  description = "Lean 4";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/6b70761ea8c896aff8994eb367d9526686501860";
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
              version = "4.0.0";
              systemName = "linux";
              hash = "sha256-CgExdbupzc8gsVImvucda7LUcnd1RIdXRakkQtsQB6o=";
            };
            "x86_64-darwin" = {
              version = "4.0.0";
              systemName = "darwin";
              hash = "sha256-+bgbXjQElwHDmwNwwRR+TpCxFeRvFoK80j5wfTOMijI=";
            };
          }.${system};
          lean4 = pkgs.stdenv.mkDerivation {
            name = "lean4";
            buildInputs = with pkgs; [
              rsync
              # stdenv.cc.cc.lib
              findutils
              file
            ] ++ lib.lists.optionals stdenv.hostPlatform.isLinux [
              #gcc-unwrapped.lib
              stdenv.cc.cc.lib
              # oldPkgs.glibc
              # llvmPackages_16.bintools-unwrapped
            ];
            nativeBuildInputs = with pkgs;
              [ makeBinaryWrapper makeWrapper ] ++
              # lib.optional stdenv.hostPlatform.isLinux pkgs.autoPatchelfHook ++
              lib.optional stdenv.hostPlatform.isDarwin fixDarwinDylibNames;
            src = pkgs.fetchzip {
              url = "https://github.com/leanprover/lean4/releases/download/v${binary.version}/lean-${binary.version}-${binary.systemName}.zip";
              hash = binary.hash;
            };
            dontAutoPatchelf = true;
            dontBuild = true;
            installPhase = with pkgs; ''
              mkdir -p $out/orig $out/bin
              rsync -a . $out/orig/
              # for cmd in clang lake ld.lld lean leanc leanmake llvm-ar; do
              #   makeWrapper $out/orig/bin/$cmd $out/bin/$cmd \
              #     --set LD_PRELOAD \
              #     "${stdenv.cc.cc.lib}/lib/libgcc_s.so.1:${glibc}/lib/libc.so.6:${glibc}/lib/libdl.so.2:${glibc}/lib/libm.so.6:${glibc}/lib/libpthread.so.0:${glibc}/lib/librt.so.1:${zlib}/lib/libz.so.1"
              # done
            '';
            # autoPatchelfIgnoreMissingDeps = [
            #   "libgcc_s.so.1"
            # ];
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
                echo "install_nae_tool done in Darwin"
              '' +
              # | xargs patchelf --set-rpath \
              # "${stdenv.cc.cc.lib}/lib:${glibc}/lib:${libcxx}/lib:${libcxxabi}/lib:${llvmPackages_14.libunwind}/lib:${zlib}/lib:$out/lib"
              lib.strings.optionalString stdenv.hostPlatform.isLinux ''
                find $out -type f -exec file {} \; | grep ELF \
                  | cut -d: -f1 | grep -v '\.o$' \
                  | xargs patchelf --set-rpath \
                  "${stdenv.cc.cc.lib}/lib:${glibc}/lib:${zlib}/lib:${libcxx}/lib:${libcxxabi}/lib:${llvmPackages_15.libllvm.lib}/lib:${llvmPackages_15.libunwind}/lib:"'$ORIGIN/../lib/lean'
                #   # "$out/lib:$out/lib/glibc:$out/lib/lean:'
                # mkdir -p $out/orig/mylib
                # ln -s $out/orig/lib/libLLVM-15.so $out/orig/mylib/libLLVM-15.so
                # ln -s $out/orig/lib/libunwind.so.1 $out/orig/mylib/libunwind.so.1
                # patchelf --set-rpath '$ORIGIN/../mylib'":${stdenv.cc.cc.lib}/lib:${glibc}/lib:${zlib}/lib:${libcxx}/lib:${libcxxabi}/lib:${llvmPackages_15.libllvm.lib}/lib:${llvmPackages_15.libunwind}/lib:" $out/orig/bin/llvm-ar
                # patchelf --set-rpath '$ORIGIN/../mylib'":${stdenv.cc.cc.lib}/lib:${glibc}/lib:${zlib}/lib:${libcxx}/lib:${libcxxabi}/lib:${llvmPackages_15.libllvm.lib}/lib:${llvmPackages_15.libunwind}/lib:" $out/orig/lib/libLLVM-15.so
                rm $out/orig/bin/{llvm-ar,clang,ld.lld}
                ln -s ${llvmPackages_15.libllvm}/bin/llvm-ar $out/orig/bin/llvm-ar
                ln -s ${llvmPackages_15.clang-unwrapped}/bin/clang $out/orig/bin/clang
                ln -s ${llvmPackages_15.bintools}/bin/ld.lld $out/orig/bin/ld.lld

                echo "Patchelf done"
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
              "lean4.toolchainPath" = "${pkg.lean-package}";
            };
          };
        in
        {
          packages.default = lean4;
        });
}
