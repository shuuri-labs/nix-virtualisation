{ config, pkgs, lib, ... }:
let
  images = config.virtualisation.qemu.manager.images;

  # Build each enabled image: copy/fetch, unpack, convert, and install
  makeImage = name: img:
    let
      srcDrv = if lib.isString img.source then 
                  pkgs.fetchurl { url = img.source; sha256 = img.sourceSha256; } 
                else 
                  img.source;
    in
      pkgs.stdenv.mkDerivation {
        name = "qemu-image-${name}";

        # 1) fetch (with sha256) or use local
        src = srcDrv;

        # Explicitly set the phases we want to run
        phases = [ "unpackPhase" "buildPhase" "installPhase" ];

        # 2) unpack if compressedFormat is set
        unpackPhase = ''
          # Get just the filename without path
          srcFile=$(basename "$src")
          
          # If source is a directory, copy recursively
          # can probably remove since openwrt single image derivation now outputs a single file
          if [ -d "$src" ]; then
            cp -r "$src"/* .
          else
            # Copy source file to current directory
            cp "$src" "$srcFile"
            
            ${lib.optionalString (img.compressedFormat != null) ''
              case "${img.compressedFormat}" in
                # formats besides gz may also need || true or some other way to escape warning messages! untested
                zip) unzip "$srcFile"        ;;
                gz)  gunzip -f "$srcFile" || true  ;;
                bz2) bunzip2 -f "$srcFile"   ;;
                xz)  unxz -f "$srcFile"      ;;
              esac
              srcFile=''${srcFile%%.${img.compressedFormat}}
            ''}
          fi
        '';

        # 3) convert → qcow2, then maybe resize
        buildInputs = [ pkgs.qemu pkgs.xz ];

        buildPhase = ''
          outFile=${name}.qcow2

          if [ "${img.sourceFormat}" != "qcow2" ] || [ ! -f "$outFile" ]; then
            qemu-img convert \
              -f ${img.sourceFormat} \
              -O qcow2 \
              "$srcFile" \
              "$outFile"
          fi

          ${lib.optionalString (img.resizeGB != null) ''
            qemu-img resize "$outFile" ${toString img.resizeGB}G
          ''}
        '';

        # 4) install the final qcow2
        installPhase = ''
          mkdir -p $out
          mv *.qcow2 $out/
        '';
      };

  # Build only "enabled" images into a set of derivations
  builtImages = lib.mapAttrs (name: img:
    makeImage name img
  ) (lib.filterAttrs (_: img: img.enable or false) images);
in 
{
  ##############################################################################
  # 1) Module options
  options.virtualisation.qemu.manager.images = lib.mkOption {
    type        = lib.types.attrsOf (lib.types.submodule ({
      options = {
        enable = lib.mkEnableOption "Build and convert this QEMU image";


        source = lib.mkOption {
          type        = lib.types.nullOr (lib.types.either lib.types.str lib.types.package);
          default     = null;
          description = ''
            Remote URL or local path to fetch the image from.
            If local path, prefix with: file://
          '';
        };

        sourceSha256 = lib.mkOption {
          type        = lib.types.nullOr lib.types.str;
          default     = null;
          description = '' 
            Required if `source` is a remote URL.  
            If source is a local path, prefix with: file://
            You can get the sha256 by running `nix-prefetch-url <url>`
          '';
        };

        sourceFormat = lib.mkOption {
          type        = lib.types.enum [ "raw" "vmdk" "vdi" "vhdx" "qcow" "qcow2" ];
          default     = "raw";
          description = "Format of the source image.";
        };

        compressedFormat = lib.mkOption {
          type        = lib.types.nullOr (lib.types.enum [ "zip" "gz" "bz2" "xz" ]);
          default     = null;
          description = "Decompression type, if the source is an archive.";
        };

        resizeGB = lib.mkOption {
          type        = lib.types.nullOr lib.types.ints.positive;
          default     = null;
          description = "If set, resize the resulting qcow2 to this size in GiB.";
        };
      };
    }));
    default     = { };
    description = "Declarative download/unzip/convert of VM images to qcow2.";
  };

  options.virtualisation.qemu.manager.builtImages = lib.mkOption {
    type = lib.types.attrs;
    internal = true;
    default = builtImages;
    description = "Internal: built image derivations";
  };

  # 2) Emit /etc/qemu-images.json once any image is enabled
  config = lib.mkIf (lib.any (img: img.enable) (lib.attrValues images)) {
     environment.etc."qemu-images.json".text = builtins.toJSON (
       lib.mapAttrs (name: drv: {
         path = "${drv}/${name}.qcow2";
         format = "qcow2";  # All our converted images are qcow2
       }) builtImages
     );
   };
}


