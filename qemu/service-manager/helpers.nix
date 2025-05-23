{ lib, pkgs }:

rec {
  mkTapArgs = taps: smp:
    lib.flatten (lib.imap0 (idx: tap: [
      "-netdev" "tap,id=net${toString idx},br=br0,helper=/run/wrappers/bin/qemu-bridge-helper"
      "-device" "virtio-net-pci,netdev=net${toString idx},mac=${tap.macAddress},mq=on,vectors=${toString (smp*2)},tx=bh"
    ]) taps);

  mkPciPassthroughArgs = hosts:
    lib.concatMap (h: [ "-device" "vfio-pci,host=${h.address}" ]) hosts;

  mkUsbPassthroughArgs = hosts:
    lib.concatMap (h: [ "-device"
      "usb-host,vendorid=${h.vendorId},productid=${h.productId}" ]) hosts;

  mkExtraArgs = extra: lib.concatMap (a: [ "-${a}" ]) extra;

  mkUefiArgs = name: enable: let
    code     = "${pkgs.OVMFFull.fd}/FV/OVMF_CODE.fd";
    varsFile = "/var/lib/libvirt/images/${name}-ovmf-vars.fd";
  in
    lib.optional enable "-drive if=pflash,format=raw,readonly=on,file=${code}"
  ++ lib.optional enable "-drive if=pflash,format=raw,file=${varsFile}";

  mkUefiPreStart = name: enable: 
    if enable then ''
      ${pkgs.coreutils}/bin/install -m0644 -o root -D \
        ${pkgs.OVMFFull.fd}/FV/OVMF_VARS.fd /var/lib/libvirt/images/${name}-ovmf-vars.fd
    '' else "";

  prettyArgs = args: lib.concatStringsSep " \\\n  " args;
}
