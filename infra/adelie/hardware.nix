{
  config,
  inputs,
  lib,
  ...
}:

{
  nixpkgs.hostPlatform = "x86_64-linux";

  imports = [
    inputs.nixos-hardware.nixosModules.common-cpu-amd
    ../common/nixos/nvidia-wayland.nix
    inputs.nixos-hardware.nixosModules.common-pc-ssd
  ];

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  boot.initrd.availableKernelModules = [
    "nvme"
    "xhci_pci"
    "ahci"
    "usbhid"
    "usb_storage"
    "sd_mod"
  ];
  boot.kernelModules = [ "kvm-amd" ];

  hardware.enableRedistributableFirmware = true;
  hardware.cpu.amd.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;

  /*
    Adelie's RTX 2060 Super renders its local Wayland sessions through the
    production NVIDIA driver. Display support does not grant any service GPU
    device nodes; nori.gpu.nvidiaDevices remains at its shared empty default.
  */
  services.xserver.videoDrivers = [ "nvidia" ];
  hardware.graphics.enable = true;
  hardware.nvidia = {
    open = true;
    modesetting.enable = true;
    # Bigscreen and browser clients use NVIDIA's VA-API translation driver.
    videoAcceleration = true;
    package = config.boot.kernelPackages.nvidiaPackages.production;
  };
}
