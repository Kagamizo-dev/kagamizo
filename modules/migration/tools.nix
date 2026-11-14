# The migration's tools, pinned (modules/catalog/sources.nix lists them):
#
#   icloudpd     iCloud Photos, originals and metadata (Apple password + 2FA)
#   pyicloud     iCloud Notes, Reminders, Contacts, Calendars, as a library
#   rclone       iCloud Drive (iclouddrive), Google Drive (drive), Proton
#                Drive (protondrive, beta: every copy is checked by hash)
#   vdirsyncer   CardDAV and CalDAV to vCard and ICS
#   imapsync     IMAP to IMAP: iCloud Mail into Proton through Bridge
{ inputs, ... }:
{
  perSystem =
    { pkgs, ... }:
    let
      icloudpd = pkgs.icloudpd.overrideAttrs (_: {
        version = "1.32.3";
        src = inputs.icloudpd-src;
      });
      # Its floors on certifi (the CA bundle), fido2 (security-key sign-in,
      # unused here) and pydantic (2.13 over the pinned 2.12) are above the
      # pinned nixpkgs'; relaxed, and its own tests run against them.
      py = pkgs.python3Packages;
      # tinyhtml (MIT/Apache-2.0), which pyicloud renders Notes with; not
      # in nixpkgs. PyPI's wheel, pinned by hash.
      tinyhtml = py.buildPythonPackage rec {
        pname = "tinyhtml";
        version = "1.3.0";
        format = "wheel";
        src = pkgs.fetchurl {
          url = "https://files.pythonhosted.org/packages/py3/t/tinyhtml/tinyhtml-${version}-py3-none-any.whl";
          sha256 = "b9a726fd3332f0a6c6ef8ef501cb1aabb6bad23ac98a61ae6ac321c605439c4b";
        };
      };
      pyicloud = py.pyicloud.overridePythonAttrs (old: {
        version = "2026.10.1";
        src = inputs.pyicloud-src;
        nativeCheckInputs = (old.nativeCheckInputs or [ ]) ++ [ py.pytest-timeout ];
        # Its 2-second test timeout is too short for the build sandbox.
        pytestFlags = (old.pytestFlags or [ ]) ++ [ "--timeout=30" ];
        dependencies = (old.dependencies or [ ]) ++ [
          py.protobuf
          py.pydantic
          py.typer
          py.rich
          tinyhtml
        ];
        pythonRelaxDeps = (old.pythonRelaxDeps or [ ]) ++ [
          "certifi"
          "fido2"
          "pydantic"
        ];
      });
    in
    {
      packages = {
        inherit icloudpd;
        inherit (pkgs) rclone vdirsyncer imapsync;
        migration-python = pkgs.python3.withPackages (_: [ pyicloud ]);
      };
    };
}
