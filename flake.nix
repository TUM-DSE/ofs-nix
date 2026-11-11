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
  };

  outputs =
    {
      nixpkgs,
      flake-utils,
      fpga-nix,
      opae-sdk,
      ...
    }:
    flake-utils.lib.eachSystem [ "x86_64-linux" ] (
      system:
      let
        pkgs = import nixpkgs { inherit system; };
        opae = pkgs.callPackage ./pkgs/opae-sdk.nix {
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
      {
        packages = {
          inherit opae;
          default = opae;
        };

        # Every tool starts: libraries resolve, Python modules import and
        # embedded Python finds OPAE's modules. Without a device or /sys, tools
        # may still exit with an error, so only loader, import and crash
        # failures count.
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
    );
}
