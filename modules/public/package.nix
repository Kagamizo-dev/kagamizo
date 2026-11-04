# Public's official CLI (brokerage: accounts, portfolio, market data,
# preflight and orders), built from its pinned release source (flake input
# publicdotcom-cli) with this flake's nixpkgs.
{ inputs, ... }:
{
  perSystem =
    { pkgs, ... }:
    {
      packages.public = pkgs.python3Packages.buildPythonApplication {
        pname = "publicdotcom-cli";
        version = "1.3.7";
        src = inputs.publicdotcom-cli;
        pyproject = true;
        build-system = [ pkgs.python3Packages.hatchling ];
        dependencies = with pkgs.python3Packages; [
          attrs
          httpx
          keyring
          platformdirs
          python-dateutil
          rich
          typer
        ];
        pythonImportsCheck = [ "publicdotcom_cli" ];
        meta.mainProgram = "public";
      };
    };
}
