{
  description = "AMD AI inference stack for NixOS (XRT, xrt-plugin-amdxdna, FastFlowLM, Lemonade)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";
    rocm-systems = {
      url = "github:ROCm/rocm-systems";
      flake = false;
    };
  };

  outputs = inputs @ {flake-parts, ...}: let
    # Bump libwebsockets from 4.4.1 to 4.5.8
    libwebsocketsOverride = pkgs:
      pkgs.libwebsockets.overrideAttrs (old: rec {
        version = "4.5.8";
        src = pkgs.fetchFromGitHub {
          owner = "warmcat";
          repo = "libwebsockets";
          rev = "v${version}";
          hash = "sha256-0pLBxOSKaxboHd9L27RKKqSJ9lVH4wPgKSyXEoJMal4=";
        };
        patches = [];
        postInstall = (old.postInstall or "") + ''
          for pc in "$out"/lib/pkgconfig/*.pc "$dev"/lib/pkgconfig/*.pc; do
            [ -f "$pc" ] || continue
            sed -i \
              -e "s|^libdir=.*$|libdir=$out/lib|" \
              -e "s|^includedir=.*$|includedir=$dev/include|" \
              "$pc"
          done
        '';
      });

    # ── ROCm nightly overlay ──────────────────────────────────────────
    # Overrides rocmPackages with sources from ROCm's develop monorepo.
    rocmNightlyOverlay = import ./overlays/rocm-nightly.nix {inherit (inputs) rocm-systems;};

    rocmNightlyPkgs = import inputs.nixpkgs {
      system = "x86_64-linux";
      overlays = [ rocmNightlyOverlay ];
    };
  in
    flake-parts.lib.mkFlake {inherit inputs;} {
      systems = ["x86_64-linux"];

      flake = {
        overlays = {
          default = final: prev: let
            pinned = import inputs.nixpkgs {inherit (final.stdenv.hostPlatform) system;};
            libwebsockets = libwebsocketsOverride pinned;
            xrt = pinned.callPackage ./pkgs/xrt {};
            fastflowlm = pinned.callPackage ./pkgs/fastflowlm {inherit xrt;};
            llama-cpp = pinned.llama-cpp;
            llama-cpp-vulkan = pinned.llama-cpp.override {vulkanSupport = true;};
            llama-cpp-rocm = pinned.llama-cpp-rocm;
            whisper-cpp-vulkan = pinned.whisper-cpp.override {vulkanSupport = true;};
            stable-diffusion-cpp-rocm = pinned.stable-diffusion-cpp.override {rocmSupport = true;};
          in {
            inherit xrt fastflowlm llama-cpp llama-cpp-vulkan llama-cpp-rocm libwebsockets;
            inherit whisper-cpp-vulkan stable-diffusion-cpp-rocm;
            xrt-plugin-amdxdna = pinned.callPackage ./pkgs/xrt-plugin-amdxdna {inherit xrt;};
            lemonade = pinned.callPackage ./pkgs/lemonade {
              inherit fastflowlm llama-cpp-vulkan llama-cpp-rocm libwebsockets;
              inherit whisper-cpp-vulkan stable-diffusion-cpp-rocm;
              inherit (pinned) whisper-cpp stable-diffusion-cpp;
            };
            gaia = pinned.callPackage ./pkgs/gaia {};
          };
          rocm-nightly = rocmNightlyOverlay;
        };

        nixosModules.default = {
          imports = [./modules/amd-npu.nix];
          nixpkgs.overlays = [inputs.self.overlays.default];
          _module.args.rocmNightlyOverlay = inputs.self.overlays.rocm-nightly;
        };
      };

      perSystem = {
        pkgs,
        system,
        ...
      }: let
        xrt = pkgs.callPackage ./pkgs/xrt {};
        fastflowlm = pkgs.callPackage ./pkgs/fastflowlm {inherit xrt;};
        llama-cpp = pkgs.llama-cpp;
        llama-cpp-vulkan = pkgs.llama-cpp.override {vulkanSupport = true;};
        llama-cpp-rocm = pkgs.llama-cpp-rocm;
        whisper-cpp-vulkan = pkgs.whisper-cpp.override {vulkanSupport = true;};
        stable-diffusion-cpp-rocm = pkgs.stable-diffusion-cpp.override {rocmSupport = true;};
        libwebsockets = libwebsocketsOverride pkgs;
      in {
        packages = {
          inherit xrt fastflowlm llama-cpp llama-cpp-vulkan llama-cpp-rocm libwebsockets;
          inherit whisper-cpp-vulkan stable-diffusion-cpp-rocm;
          xrt-plugin-amdxdna = pkgs.callPackage ./pkgs/xrt-plugin-amdxdna {inherit xrt;};
          lemonade = pkgs.callPackage ./pkgs/lemonade {
            inherit fastflowlm llama-cpp-vulkan llama-cpp-rocm libwebsockets;
            inherit whisper-cpp-vulkan stable-diffusion-cpp-rocm;
            whisper-cpp = pkgs.whisper-cpp;
            stable-diffusion-cpp = pkgs.stable-diffusion-cpp;
          };
          gaia = pkgs.callPackage ./pkgs/gaia {};
          benchmark = pkgs.callPackage ./pkgs/benchmark-go {};
          # ROCm nightly variants
          llama-cpp-rocm-nightly = rocmNightlyPkgs.llama-cpp-rocm;
          stable-diffusion-cpp-rocm-nightly = rocmNightlyPkgs.stable-diffusion-cpp.override {rocmSupport = true;};
        };

        checks = {
          module-eval-rocm-nightly = (inputs.nixpkgs.lib.nixosSystem {
            inherit system;
            modules = [
              inputs.self.nixosModules.default
              {
                boot.loader.grub.enable = false;
                fileSystems."/" = { device = "/dev/sda1"; fsType = "ext4"; };
                hardware.amd-npu = {
                  enable = true;
                  enableROCm = true;
                  useRocmNightly = true;
                  lemonade.user = "testuser";
                };
                users.users.testuser = {
                  isNormalUser = true;
                  extraGroups = ["video" "render"];
                };
              }
            ];
          }).config.system.build.etc;

          module-eval-rocm-false = (inputs.nixpkgs.lib.nixosSystem {
            inherit system;
            modules = [
              inputs.self.nixosModules.default
              {
                boot.loader.grub.enable = false;
                fileSystems."/" = { device = "/dev/sda1"; fsType = "ext4"; };
                hardware.amd-npu = {
                  enable = true;
                  enableFastFlowLM = true;
                  enableLemonade = true;
                  enableROCm = false;
                  lemonade.user = "testuser";
                };
                users.users.testuser = {
                  isNormalUser = true;
                  extraGroups = ["video" "render"];
                };
              }
            ];
          }).config.system.build.etc;

          module-eval-rocm-true = (inputs.nixpkgs.lib.nixosSystem {
            inherit system;
            modules = [
              inputs.self.nixosModules.default
              {
                boot.loader.grub.enable = false;
                fileSystems."/" = { device = "/dev/sda1"; fsType = "ext4"; };
                hardware.amd-npu = {
                  enable = true;
                  enableFastFlowLM = true;
                  enableLemonade = true;
                  enableROCm = true;
                  lemonade.user = "testuser";
                };
                users.users.testuser = {
                  isNormalUser = true;
                  extraGroups = ["video" "render"];
                };
              }
            ];
          }).config.system.build.etc;

          module-eval-vulkan-true = (inputs.nixpkgs.lib.nixosSystem {
            inherit system;
            modules = [
              inputs.self.nixosModules.default
              {
                boot.loader.grub.enable = false;
                fileSystems."/" = { device = "/dev/sda1"; fsType = "ext4"; };
                hardware.amd-npu = {
                  enable = true;
                  enableFastFlowLM = true;
                  enableLemonade = true;
                  enableROCm = false;
                  enableVulkan = true;
                  lemonade.user = "noams";
                };
                users.users.noams = {
                  isNormalUser = true;
                  extraGroups = ["video" "render"];
                };
              }
            ];
          }).config.system.build.etc;

          module-eval-gtt = let
            mkSys = extra: (inputs.nixpkgs.lib.nixosSystem {
              inherit system;
              modules = [
                inputs.self.nixosModules.default
                {
                  boot.loader.grub.enable = false;
                  fileSystems."/" = { device = "/dev/sda1"; fsType = "ext4"; };
                  hardware.amd-npu = {
                    enable = true;
                    lemonade.user = "testuser";
                  } // extra;
                  users.users.testuser = {
                    isNormalUser = true;
                    extraGroups = ["video" "render"];
                  };
                }
              ];
            }).config.boot.extraModprobeConfig;
            configured = mkSys {
              gpuMemory = { ttmSizeGiB = 120; pagePoolSizeGiB = 60; };
            };
            ttmOnly = mkSys {
              gpuMemory = { ttmSizeGiB = 10; };
            };
            default = mkSys {};
          in
            pkgs.runCommand "module-eval-gtt" {
              inherit configured ttmOnly default;
            } ''
              echo "$configured" | grep -F 'options ttm pages_limit=31457280 page_pool_size=15728640'
              echo "$ttmOnly" | grep -F 'options ttm pages_limit=2621440'
              echo "$ttmOnly" | grep -vq 'page_pool_size' || { echo "ttm-only must not set page_pool_size"; exit 1; }
              echo "$default" | grep -vq 'pages_limit' || { echo "default must not set pages_limit"; exit 1; }
              touch $out
            '';
        };

        apps.benchmark = {
          type = "app";
          program = "${pkgs.callPackage ./pkgs/benchmark-go {}}/bin/benchmark";
          meta = {description = "Benchmark lemonade backends — interactive TUI or headless (ROCm, Vulkan, FLM)";};
        };
      };
    };
}
