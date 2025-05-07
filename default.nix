{ config, lib, pkgs, ... }:

let
  cfg = config.virtualisation;
in
{
  imports = [
    ./base.nix
    ./bare-metal.nix
    ./intel.nix
    ./qemu/service-manager
    ./qemu/image-manager
  ];

  config = {
    virtualisation.base.enable = cfg.bareMetal.enable || cfg.intel.enable;
    virtualisation.bareMetal.enable = cfg.intel.enable;
  };
}


