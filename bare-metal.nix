{ config, lib, ... }:

let
  cfg = config.virtualisation.bareMetal; 
in
{
  options.virtualisation.bareMetal = {
    enable = lib.mkEnableOption "bare metal virtualisation";
  };

  config = lib.mkIf cfg.enable {
    boot = {
      kernelParams = [ "iommu=on" "iommu=pt" ];
      initrd.kernelModules = [ "vfio_iommu_type1" "vfio_pci" ];
    };
  };
}