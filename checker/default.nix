{ python3Packages, ... }:

python3Packages.buildPythonApplication {
  pname = "evilnt-maid-checker";
  version = "0.1";

  src = ./.;

  propagatedBuildInputs = with python3Packages; [
    flask
    cryptography
  ];

  postInstall = ''
    mkdir -p $out/share/
    cp -r assets $out/share/EVMassets
  '';

  postFixup = ''
    mv $out/bin/{main.py,EVMchecker}
    wrapProgram $out/bin/EVMchecker \
        --set EVM_ASSETS $out/share/EVMassets
  '';

  pyproject = true;
  build-system = [python3Packages.setuptools];
}
