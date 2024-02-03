{
  description = "Description for the project";

  inputs = {
    devshell.url = "github:numtide/devshell";
    devshell.inputs.nixpkgs.follows = "nixpkgs";
    flake-compat.url = "github:edolstra/flake-compat";
    flake-parts.url = "github:hercules-ci/flake-parts";
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-23.11";
    treefmt-nix.url = "github:numtide/treefmt-nix";
    treefmt-nix.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = inputs:
    inputs.flake-parts.lib.mkFlake {inherit inputs;} ({inputs, ...}: {
      systems = [
        "aarch64-darwin"
        "aarch64-linux"
        "x86_64-darwin"
        "x86_64-linux"
      ];

      imports = [
        inputs.devshell.flakeModule
        inputs.treefmt-nix.flakeModule
      ];

      perSystem = {
        config,
        lib,
        pkgs,
        system,
        ...
      }: {
        devshells.default = {
          commands = [
            {
              category = "dev";
              package = pkgs.ansible;
            }

            {
              category = "dev";
              package = pkgs.vagrant.override {
                # So that we can use `libguestfs-with-appliance` when calling
                # `create-box` (by default, the `vagrant` derivation depends on
                # plain old `libguestfs`).
                libguestfs = pkgs.libguestfs-with-appliance;
              };
            }

            {
              category = "dev";
              package = config.packages.vagrant-libvirt-create-box;
            }

            {
              name = "fmt";
              category = "dev";
              help = "Format this project's code";
              command = ''
                exec ${config.treefmt.build.wrapper}/bin/treefmt "$@"
              '';
            }
          ];

          devshell.packages = with pkgs; [
            curl
            guestfs-tools
            gzip
            libguestfs-with-appliance
            qemu
            sshpass # for password auth with Ansible
          ];
        };

        packages = let
          rpi4 = inputs.nixpkgs.lib.nixosSystem {
            inherit system;

            modules = [
              {
                nixpkgs.crossSystem.system = "aarch64-linux";
              }
              ./configuration.nix
            ];
          };
        in {
          rpi4-initrd = rpi4.config.system.build.initialRamdisk;
          rpi4-kernel = rpi4.config.system.build.kernel;

          # From the `vagrant-libvirt` project.  Patched to permit injecting
          # additional files into the generated Vagrant box archive.
          vagrant-libvirt-create-box =
            pkgs.runCommand "vagrant-libvirt-create-box" {
              src = pkgs.fetchurl {
                url = "https://raw.githubusercontent.com/vagrant-libvirt/vagrant-libvirt/main/tools/create_box.sh";
                sha256 = "sha256-xrCoMeXV++Dmi766r0i0RO4NMe7LDr3jNdJSXjNrY+4=";
              };

              nativeBuildInputs = with pkgs; [
                makeWrapper
              ];

              meta = {
                mainProgram = "vagrant-libvirt-create-box";
                description = "create a Vagrant box file from a qcow2 disk image";
              };
            } ''
              script="''${out}/bin/vagrant-libvirt-create-box"
              install -D "$src" "$script"
              sed -i -e '/^tar[[:space:]]\+cv/ {
                s/^tar\([[:space:]]\+\)/tar --transform="s|.*\/||"\1-/
                s/\([[:space:]]\+\)|\([[:space:]]\+\)/\1"$@" |\2/
                s/^/argc="$#"; if [ "$argc" -ge 3 ]; then shift 3; elif [ "$argc" -eq 2 ]; then shift 2; else shift 1; fi; /
              }' "$script"
              wrapProgram "$script" --prefix PATH : ${lib.makeBinPath (with pkgs; [coreutils gawk gnutar pigz psmisc qemu])}
            '';
        };

        treefmt = {
          programs.alejandra.enable = true;
          flakeFormatter = true;
          projectRootFile = "flake.nix";
        };
      };

      flake = {
        nixosConfigurations = {
          rpi4 = inputs.nixpkgs.lib.nixosSystem {
            system = "aarch64-linux";
            modules = [
              ./configuration.nix
            ];
          };
        };
      };
    });
}
