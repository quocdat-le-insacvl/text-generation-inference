{
  inputs = {
    crate2nix = {
      url = "github:nix-community/crate2nix";
      inputs.nixpkgs.follows = "tgi-nix/nixpkgs";
    };
    tgi-nix.url = "github:danieldk/tgi-nix";
    nixpkgs.follows = "tgi-nix/nixpkgs";
    flake-utils.url = "github:numtide/flake-utils";
    poetry2nix.url = "github:nix-community/poetry2nix";
    rust-overlay = {
      url = "github:oxalica/rust-overlay";
      inputs.nixpkgs.follows = "tgi-nix/nixpkgs";
    };
  };
  outputs =
    {
      self,
      crate2nix,
      nixpkgs,
      flake-utils,
      rust-overlay,
      tgi-nix,
      poetry2nix,
    }:
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        cargoNix = crate2nix.tools.${system}.appliedCargoNix {
          name = "tgi";
          src = ./.;
          additionalCargoNixArgs = [ "--all-features" ];
        };
        config = {
          allowUnfree = true;
          cudaSupport = true;
        };
        pkgs = import nixpkgs {
          inherit config system;
          overlays = [
            rust-overlay.overlays.default
            tgi-nix.overlay
          ];
        };
        inherit (poetry2nix.lib.mkPoetry2Nix { inherit pkgs; }) mkPoetryEditablePackage;
        text-generation-server = mkPoetryEditablePackage { editablePackageSources = ./server; };
      in
      {
        devShells.default =
          with pkgs;
          mkShell {
            buildInputs =
              [
                openssl.dev
                pkg-config
                (rust-bin.stable.latest.default.override {
                  extensions = [
                    "rust-analyzer"
                    "rust-src"
                  ];
                })
              ]
              ++ (with python3.pkgs; [
                venvShellHook
                pip

                causal-conv1d
                click
                einops
                exllamav2
                fbgemm-gpu
                flashinfer
                flash-attn
                flash-attn-layer-norm
                flash-attn-rotary
                grpc-interceptor
                grpcio-reflection
                grpcio-status
                grpcio-tools
                hf-transfer
                loguru
                mamba-ssm
                marlin-kernels
                opentelemetry-api
                opentelemetry-exporter-otlp
                opentelemetry-instrumentation-grpc
                opentelemetry-semantic-conventions
                peft
                tokenizers
                torch
                transformers
                vllm

                cargoNix.workspaceMembers.text-generation-launcher.build

                (cargoNix.workspaceMembers.text-generation-router-v3.build.override {
                  crateOverrides = defaultCrateOverrides // {
                    aws-lc-rs = attrs: {
                      # aws-lc-rs does its own custom parsing of Cargo environment
                      # variables like DEP_.*_INCLUDE. However buildRustCrate does
                      # not use the version number, so the parsing fails.
                      postPatch = ''
                        substituteInPlace build.rs \
                          --replace-fail \
                          "assert!(!selected.is_empty()" \
                          "// assert!(!selected.is_empty()"
                      '';
                    };
                    rav1e = attrs: { env.CARGO_ENCODED_RUSTFLAGS = "-C target-feature=-crt-static"; };
                    text-generation-router-v3 = attrs: {
                      # We need to do the src/source root dance so that the build
                      # has access to the protobuf file.
                      src = ./.;
                      postPatch = "cd backends/v3";
                      buildInputs = [ protobuf ];
                    };
                  };
                })
              ]);

            venvDir = "./.venv";

            postVenv = ''
              unset SOURCE_DATE_EPOCH
            '';
            postShellHook = ''
              unset SOURCE_DATE_EPOCH
            '';
          };
      }
    );
}
