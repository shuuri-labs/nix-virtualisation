{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils, ... }: {
    nixosModules.default = ./default.nix;
    
    # Export the QEMU library for external use
    lib = import ./qemu/lib.nix { lib = nixpkgs.lib; };
  };
}