{
  description = "Nix tooling for Intel Open FPGA Stack (OFS) development";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";
    flake-utils.url = "github:numtide/flake-utils";
    fpga-nix = {
      url = "github:TUM-DSE/fpga-nix/feature/intel-quartus";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.flake-utils.follows = "flake-utils";
    };
    # OPAE 2.13.0-3 is the version OFS 2024.2 was released with.
    opae-sdk = {
      url = "github:OFS/opae-sdk/2.13.0-3";
      flake = false;
    };
    # The OFS 2024.2 FIM for Agilex 7 PCIe attach boards. It is the newest
    # release for Quartus 24.1, which also needs patches 0.18 and 0.26.
    ofs-agx7-pcie-attach = {
      type = "git";
      url = "https://github.com/OFS/ofs-agx7-pcie-attach";
      ref = "refs/tags/ofs-2024.2-1";
      submodules = true;
      flake = false;
    };
    ofs-platform-afu-bbb = {
      url = "github:OFS/ofs-platform-afu-bbb/ofs-2024.2-1";
      flake = false;
    };
    # Out-of-tree DFL drivers. The branch moves, so pin the commit.
    linux-dfl-backport = {
      url = "github:OFS/linux-dfl-backport/1d01b806f5bd7c65e2e46c37d43ba4aa6a4a047c";
      flake = false;
    };
  };

  outputs =
    {
      nixpkgs,
      flake-utils,
      fpga-nix,
      opae-sdk,
      linux-dfl-backport,
      ofs-agx7-pcie-attach,
      ofs-platform-afu-bbb,
      ...
    }:
    let
      dflDriverVersion = "6.6-lts";
      ofsLib = {
        mkDflDriverPackages =
          args:
          import ./lib/mkDflDriverPackages.nix (
            {
              src = linux-dfl-backport;
              version = dflDriverVersion;
            }
            // args
          );

        # Defaults to the pinned OFS 2024.2 FIM, its platform BBB and OPAE.
        mkOfsFimPackage =
          args:
          import ./lib/mkOfsFimPackage.nix (
            {
              fpgaNixLib = fpga-nix.lib;
              src = ofs-agx7-pcie-attach;
              platformAfuBbb = ofs-platform-afu-bbb;
              opae = opaeFor args.pkgs;
            }
            // args
          );

        # The Quartus version the pinned OFS release needs.
        quartusVersion = "24.1";
      };

      opaeFor =
        pkgs:
        pkgs.callPackage ./pkgs/opae-sdk.nix {
          src = opae-sdk;
          version = "2.13.0-3";
          # OPAE pins CLI11 2.1.2. Newer versions reject some of its option names.
          cli11 = pkgs.cli11.overrideAttrs (_: rec {
            version = "2.1.2";
            # Header-only; skip tests and examples written for older tools.
            cmakeFlags = [
              "-DCMAKE_POLICY_VERSION_MINIMUM=3.5"
              "-DCLI11_BUILD_TESTS=OFF"
              "-DCLI11_BUILD_EXAMPLES=OFF"
            ];
            doCheck = false;
            src = pkgs.fetchFromGitHub {
              owner = "CLIUtils";
              repo = "CLI11";
              rev = "v${version}";
              hash = "sha256-I150pDmaHY+RbHMr28f4xdggMB2ZhUNBGgOcsvuiQ3w=";
            };
          });
        };
    in
    flake-utils.lib.eachSystem [ "x86_64-linux" ] (
      system:
      let
        pkgs = import nixpkgs {
          inherit system;
          # Only the prebuilt FIM images, which contain Intel IP, are unfree.
          config.allowUnfreePredicate =
            pkg: nixpkgs.lib.hasPrefix "ofs-fim-images-" (nixpkgs.lib.getName pkg);
        };
        opae = opaeFor pkgs;
      in
      {
        packages = {
          inherit opae;
          fim-images-iseries-dk = pkgs.callPackage ./pkgs/fim-images.nix {
            release = "2024.2-1";
            board = "iseries-dk";
            hash = "sha256-VqRiNe0TmoJ0gPAoJLVBLPWsGhjpooyqZWnCotV7VWE=";
          };
          default = opae;
        };

        # Every tool starts: libraries resolve, Python modules import and
        # embedded Python finds OPAE's modules. Without a device or /sys, tools
        # may still exit with an error, so only loader, import and crash
        # failures count.
        # The drivers build against the kernel series of the backport branch.
        # Sites build them for their own kernels with lib.mkDflDriverPackages.
        checks.dfl-drivers = pkgs.callPackage ./pkgs/dfl-drivers.nix {
          src = linux-dfl-backport;
          version = dflDriverVersion;
          kernel = pkgs.linuxPackages_6_6.kernel;
        };

        # The FIM needs Quartus and a license to build, so only check that it
        # evaluates for the I-Series dev kit with the PR template.
        checks.fim-eval =
          let
            quartusShareRoot = "/nonexistent/intel-fpga/tools";
            fim = ofsLib.mkOfsFimPackage {
              inherit pkgs quartusShareRoot;
              intelTools = fpga-nix.lib.mkIntelTools { inherit pkgs quartusShareRoot; };
              inherit (ofsLib) quartusVersion;
              target = "iseries-dk";
            };
          in
          pkgs.writeText "ofs-nix-fim-eval" (builtins.unsafeDiscardOutputDependency fim.drvPath);

        checks.opae-tools = pkgs.runCommand "ofs-nix-opae-tools" { } ''
          ${opae}/bin/fpgainfo --version | grep -F 2.13.0
          failed=0
          for tool in ${opae}/bin/*; do
            name="$(basename "$tool")"
            case "$name" in .*) continue ;; esac
            status=0
            output="$(timeout 15 "$tool" --help 2>&1 < /dev/null)" || status=$?
            # 124 is a timeout and 129 to 192 a signal, such as an abort.
            if [ "$status" = 124 ] || { [ "$status" -ge 129 ] && [ "$status" -le 192 ]; } ||
              printf '%s' "$output" |
              grep -qE 'error while loading shared|ModuleNotFoundError|ImportError|Traceback'; then
              echo "FAIL $name (exit $status):" >&2
              printf '%s\n' "$output" | head -5 >&2
              failed=1
            fi
          done
          [ "$failed" = 0 ]
          touch "$out"
        '';

        devShells.default = pkgs.mkShell {
          packages = [
            pkgs.nixfmt
            pkgs.shellcheck
          ];
        };

        formatter = pkgs.nixfmt-tree;
      }
    )
    // {
      lib = ofsLib;
    };
}
