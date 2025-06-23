{ config, pkgs, lib, ... }:
{
  imports = [
    ./image-manager
    ./service-manager
    ./options.nix
  ];
}