nzcpkgs:

{ pkgs, lib, config, ... }:

let cfg = config.boot.evilnt-maid;
    luks-filesystems = builtins.attrNames config.boot.initrd.luks.devices;
    defaultFsKernelModules = {
      "vfat" = ["vfat" "nls_cp437" "nls_iso8859_1"];
    };
    evilnt-maid-attest =
      pkgs.writeShellApplication {
        name = "EVMattest";
        text = builtins.readFile ./scripts/attest.sh;
        runtimeInputs = with pkgs; [
          nzc
          tpm2-tools
          qrcode
          openssl
          toybox
          gawk
        ];
      };
    evilnt-maid-setup =
      pkgs.writeShellApplication {
        name = "EVMsetup";
        text = builtins.readFile ./scripts/setup.sh;
        runtimeInputs = with pkgs; [
          tpm2-tools
          openssl
          toybox
        ];
      };
    evilnt-maid-update =
      pkgs.writeShellApplication {
        name = "EVMupdate";
        text = builtins.readFile ./scripts/update.sh;
        runtimeInputs = with pkgs; [
          tpm2-tools
          openssl
          toybox
        ];
      };
in 
{
  options.boot.evilnt-maid = {
    enable = lib.mkEnableOption "Eviln't maid";
    mountBoot = lib.mkOption {
      type = lib.types.bool;
      default = true;
      example = false;
      description = ''
        Whether or not to mount /boot at boot time.

        If turned off, the mount for bootinfo will need to be created manually with
        ```
        boot.initrd.systemd.mounts = [
          {
            unitConfig.DefaultDependencies = "no";
            requiredBy = ["attest.service"];
            before = ["attest.service"];
            where = "<path>";
            what = "<device>";
          }
        ];
        ```
      '';
    };

    bootinfoPath = lib.mkOption {
      type = lib.types.singleLineStr;
      default = "/boot/EVMbootinfo";
      example = "/mnt/bootinfo";
      description = ''
        The path to bootinfo. Must be accessible in initrd.
        
        It should also be accessible by the same path in the booted system for the EVMupdate tool to work properly.
      '';
    };

    updinfoPath = lib.mkOption {
      type = lib.types.singleLineStr;
      default = "/var/lib/EVMupdinfo";
      example = "/etc/evilnt-maid/updinfo";
      description = ''
        The path to updinfo. Only used by the EVMupdate tool.
      '';
    };

    cryptsetupService = lib.mkOption {
      type = with lib.types; nullOr singleLineStr;
      default = null;
      example = "systemd-cryptsetup@crypted.service";
      description = ''
        Name of the service that decrypts the root partition.
        
        Usually `systemd-cryptsetup@<partition>.service`
      '';
    };

    ignoreKernelModules = lib.mkOption {
      type = lib.types.bool;
      default = false;
      example = true;
      description = ''
        Do not add any kernel modules for mounting /boot
      '';
    };

    fsKernelModules = lib.mkOption {
      type = with lib.types; nullOr (listOf singleLineStr);
      default = null;
      example = ["vfat" "nls_cp437" "nls_iso8859_1"];
      description = ''
        List of kernel modules to add for mounting /boot.

        Only required if /boot has an unsupported filesystem.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    assertions =
      [ { assertion = cfg.cryptsetupService == null -> builtins.length luks-filesystems == 1;
          message = ''
            Could not automatically set up boot.evilnt-maid.cryptsetupService, because multiple LUKS filesystems were found: ${lib.concatStringsSep ", " luks-filesystems}

              To fix add:
              - boot.evilnt-maid.cryptsetupService = "systemd-cryptsetup@<name>.service";

              Where the name is the one you specified earlier in you configuration:
              - initrd.luks.devices.<name>.device = ...
          '';
        }
        { assertion =
            ( cfg.mountBoot
            && !cfg.ignoreKernelModules
            && cfg.fsKernelModules == null)
            ->
            (  builtins.elem config.fileSystems."/boot".fsType (builtins.attrNames defaultFsKernelModules)
            || config.fileSystems."/boot".fsType == null);
          message = ''
            "/boot" has an unsupported filesystem.

              To fix, specify the required kernel modules using:
              - boot.evilnt-maid.fsKernelModules = [ <modules> ];
          '';
        }
        { assertion =
            ( cfg.mountBoot
            && !cfg.ignoreKernelModules
            && cfg.fsKernelModules == null)
            ->
            (config.fileSystems."/boot".fsType != null);
          message = ''
            "/boot" doesn't have the filesystem type set.

              To fix, specify the filesystem using:
              - fileSystem."/boot".fsType = "<filesystem>";
          '';
        }
      ];

    boot.initrd.kernelModules = lib.mkIf (!cfg.ignoreKernelModules) (
      if (cfg.fsKernelModules != null) then
        cfg.fsKernelModules
      else
        defaultFsKernelModules."${config.fileSystems."/boot".fsType}"
    );

    boot.initrd.systemd = {
      enable = true;
      storePaths = with pkgs; [
        evilnt-maid-attest
        nzc
        tpm2-tools
        nzc
        qrcode
        openssl
        toybox
        gawk
      ];
      mounts = lib.optional cfg.mountBoot {
        unitConfig.DefaultDependencies = "no";
        requiredBy = ["attest.service"];
        before = ["attest.service"];
        where = "/boot";
        what = config.fileSystems."/boot".device;
      };

      services.attest = {
        description = "Eviln't maid";
        wantedBy = ["local-fs-pre.target"];
        after = ["tpm2.target"];
        before = [(
          let name = (
            if cfg.cryptsetupService == null then
              builtins.elemAt luks-filesystems 0
            else
              cfg.cryptsetupService
          ); in "systemd-cryptsetup@${name}.service"
        )];
        path = [evilnt-maid-attest];
        unitConfig.DefaultDependencies = "no";
        serviceConfig = {
          Type = "oneshot";
          StandardInput = "tty-force";
          StandardOutput = "tty";
          TTYPath = "/dev/tty1";
          TTYVHangup = "yes";
        };
        script = ''
          EVMattest ${cfg.bootinfoPath}
        '';
      };
    };

    environment.systemPackages = [
      evilnt-maid-setup
      (pkgs.runCommand "evilnt-maid-update-wrapper" {} ''
        mkdir -p $out/bin
        echo '#!${pkgs.stdenv.shell}' > $out/bin/EVMupdate
        echo '${pkgs.evilnt-maid-update}/bin/EVMupdate ${cfg.bootinfoPath} ${cfg.updinfoPath}' >> $out/bin/EVMupdate
        chmod +x $out/bin/EVMupdate
      '')
    ];

    nixpkgs.overlays = [
      nzcpkgs.overlays.default
      (final: prev: {
        inherit
          evilnt-maid-attest
          evilnt-maid-setup
          evilnt-maid-update;
      })
    ];
  };
}
