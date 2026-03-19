{
  description = "A rust project";

  inputs = {
    nixpkgs.url      = "github:NixOS/nixpkgs/nixos-unstable";
    nzcpkgs = {
      url = "git+https://codeberg.org/highghlow/nzc";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    flake-utils.url  = "github:numtide/flake-utils";
  };

  outputs = { nixpkgs, flake-utils, nzcpkgs, ... }:
    {
      nixosModules.default = import ./module.nix nzcpkgs;
    }
    //
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs { inherit system; };
        nzc = nzcpkgs.packages."${system}".default;
      in
      with pkgs;
      {
        devShells.default = mkShell {
          buildInputs = [
            tpm2-tools
            nzc
            qrcode
            openssl
            (python3.withPackages (p: with p; [
              flask
              cryptography
            ]))
          ];
        };
        packages = {
          checker = pkgs.callPackage ./checker { inherit nzc; };
        };
      }
    );
}
