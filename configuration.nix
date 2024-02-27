{
  config,
  lib,
  modulesPath,
  ...
}: {
  imports = [
    "${toString modulesPath}/profiles/qemu-guest.nix"
  ];

  boot.consoleLogLevel = 8;

  boot.initrd.systemd.enable = true;

  # The serial ports listed here are:
  # - ttyS0: for Tegra (Jetson TX1)
  # - ttyAMA0: for QEMU's -machine virt
  boot.kernelParams = [
    "console=tty0"
    "console=ttyAMA0,115200n8"
    "console=ttyS0,115200n8"
  ];

  boot.loader.grub.enable = false;
  boot.loader.generic-extlinux-compatible.enable = true;

  console.earlySetup = true;

  fileSystems."/" = {
    fsType = "ext4";
    device = "/dev/disk/by-label/osmc";
  };

  hardware.enableRedistributableFirmware = true;

  networking.hostName = "osmc";
  networking.wireless.enable = false;

  system.stateVersion = "23.11";

  users.users.root.password = "osmc";
}
