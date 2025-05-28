{ lib, pkgs }:

rec {
  # Generate a simple MAC by appending a padded number to the base MAC
  genMac = vmName: idx: let
    # Generate first 5 octets from VM name hash
    nameHash = builtins.hashString "md5" vmName;
    octets = builtins.genList (i: builtins.substring (i * 2) 2 nameHash) 5;
    firstFive = builtins.concatStringsSep ":" octets;
    # Use index for last octet
    padded = builtins.substring 0 2 (builtins.concatStringsSep "" ["0" (builtins.toString idx)]);
  in "${firstFive}:${padded}";

  # Generate a deterministic MAC from an integer idx
  mkTapArgs = hostBridges: vmName: smp:
    builtins.concatLists (builtins.genList (idx: [
      "-netdev" "tap,id=${vmName}-net${builtins.toString idx},br=${builtins.elemAt hostBridges idx},helper=/run/wrappers/bin/qemu-bridge-helper,vhost=on"
      "-device" "virtio-net-pci,netdev=${vmName}-net${builtins.toString idx},mac=${genMac vmName idx},mq=on,vectors=${builtins.toString (smp*2)},tx=bh"
    ]) (builtins.length hostBridges));

  mkPciPassthroughArgs = hosts:
    builtins.concatLists (builtins.map (h: [ "-device" "vfio-pci,host=${h.address}" ]) hosts);

  mkUsbPassthroughArgs = hosts:
    builtins.concatLists (builtins.map (h: [ "-device"
      "usb-host,vendorid=${h.vendorId},productid=${h.productId}" ]) hosts);

  mkExtraArgs = extra: builtins.concatLists (builtins.map (a: [ "-${a}" ]) extra);

  mkUefiArgs = name: enable: let
    code     = "${pkgs.OVMFFull.fd}/FV/OVMF_CODE.fd";
    varsFile = "/var/lib/libvirt/images/${name}-ovmf-vars.fd";
  in
    builtins.concatLists [
      (if enable then [ "-drive" "if=pflash,format=raw,readonly=on,file=${code}" ] else [])
      (if enable then [ "-drive" "if=pflash,format=raw,file=${varsFile}" ] else [])
    ];

  mkUefiPreStart = name: enable: 
    if enable then ''
      ${pkgs.coreutils}/bin/install -m0644 -o root -D \
        ${pkgs.OVMFFull.fd}/FV/OVMF_VARS.fd /var/lib/libvirt/images/${name}-ovmf-vars.fd
    '' else "";

  prettyArgs = args: builtins.concatStringsSep " \\\n  " args;
}
