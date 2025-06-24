{ config, pkgs, lib, ... }:
let
  images = config.virtualisation.qemu.manager.images;
  baseImageDirectory = config.virtualisation.qemu.manager.baseImageDirectory;

  # Create systemd service to prepare each image
  makeImageService = name: img:
    let
      srcDrv = if lib.isString img.source then 
                 pkgs.fetchurl { url = img.source; sha256 = img.sourceSha256; } 
               else 
                 img.source;
    in {
      description = "Prepare QEMU image: ${name}";
      wantedBy = [ "multi-user.target" ];
      before = [ "qemu-${name}.service" ];
      
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ReadWritePaths = [ baseImageDirectory ];
      };

      script = ''
        set -euo pipefail
        
        # Create image directory if it doesn't exist
        mkdir -p ${baseImageDirectory}
        
        # Check if image already exists
        imageFile="${baseImageDirectory}/${name}.qcow2"
        
        if [ -f "$imageFile" ]; then
          echo "Image ${name} already exists, skipping"
          exit 0
        fi
        
        echo "Preparing image ${name}..."
        
        # Create temporary working directory
        workDir=$(mktemp -d)
        trap "rm -rf $workDir" EXIT
        cd "$workDir"
        
        # Get just the filename without path
        srcFile=$(basename "${srcDrv}")
        
        # Copy source file to working directory
        if [ -d "${srcDrv}" ]; then
          cp -r "${srcDrv}"/* .
        else
          cp "${srcDrv}" "$srcFile"
          
          ${lib.optionalString (img.compressedFormat != null) ''
            case "${img.compressedFormat}" in
              zip) ${pkgs.unzip}/bin/unzip "$srcFile" ;;
              gz)  ${pkgs.gzip}/bin/gunzip -f "$srcFile" || true ;;
              bz2) ${pkgs.bzip2}/bin/bunzip2 -f "$srcFile" ;;
              xz)  ${pkgs.xz}/bin/unxz -f "$srcFile" ;;
            esac
            srcFile=''${srcFile%%.${img.compressedFormat}}
          ''}
        fi
        
        # Convert to qcow2 if needed
        outFile="${name}.qcow2"
        if [ "${img.sourceFormat}" != "qcow2" ] || [ ! -f "$outFile" ]; then
          ${pkgs.qemu}/bin/qemu-img convert \
            -f ${img.sourceFormat} \
            -O qcow2 \
            "$srcFile" \
            "$outFile"
        fi
        
        ${lib.optionalString (img.resizeGB != null) ''
          ${pkgs.qemu}/bin/qemu-img resize "$outFile" ${toString img.resizeGB}G
        ''}
        
        # Atomically move to final location
        mv "$outFile" "$imageFile"
        
        echo "Image ${name} prepared successfully"
      '';
    };

  # Build enabled images as systemd services
  imageServices = lib.mapAttrs' (name: img: 
    lib.nameValuePair "prepare-qemu-image-${name}" (makeImageService name img)
  ) (lib.filterAttrs (_: img: img.enable or false) images);

  # Generate image metadata for /etc/qemu-images.json
  enabledImages = lib.filterAttrs (_: img: img.enable or false) images;
  imageMetadata = lib.mapAttrs (name: _: {
    path = "${baseImageDirectory}/${name}.qcow2";
    format = "qcow2";
  }) enabledImages;
in 
{
  config = lib.mkIf (enabledImages != {}) {
    # Create the image directory
    systemd.tmpfiles.rules = [ "d ${baseImageDirectory} 0755 root root - -" ];

    # Add systemd services for image preparation
    systemd.services = imageServices;

    # Emit /etc/qemu-images.json
    environment.etc."qemu-images.json".text = builtins.toJSON imageMetadata;
  };
}


