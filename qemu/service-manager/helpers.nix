{ lib, pkgs }:

rec {
  genRandomMAC = hostName: let
    base = builtins.hashString "md5" hostName;
    bytes = builtins.substring 0 12 base;
    formatted = builtins.concatStringsSep ":" (builtins.genList (i: builtins.substring (i * 2) 2 bytes) 6);
  in formatted;

  # Generate a deterministic MAC from an integer idx
  mkTapArgs = hostBridges: smp:
    builtins.concatLists (builtins.genList (idx: [
      "-netdev" "tap,id=net${builtins.toString idx},br=${builtins.elemAt hostBridges idx},helper=/run/wrappers/bin/qemu-bridge-helper,vhost=on"
      "-device" "virtio-net-pci,netdev=net${builtins.toString idx},mq=on,vectors=${builtins.toString (smp*2)},tx=bh" # ,mac=${genRandomMAC (builtins.toString idx)}
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
