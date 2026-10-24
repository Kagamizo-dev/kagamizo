{
  description = "NixOS images and the Kagamizo identity (Cloudflare, Proton Pass) as code";

  # Pinned by flake.lock. Upstream follows the stable nixos-26.05 channel, so
  # the base only moves when `nix flake update` is run on purpose.
  inputs = {
    nixos-raspberrypi.url = "git+https://github.com/nvmd/nixos-raspberrypi?ref=main";
    # The images' nixpkgs, shared by everything else in the flake.
    nixpkgs.follows = "nixos-raspberrypi/nixpkgs";

    # Dendritic layout: every file under ./modules is a flake-parts module.
    flake-parts = {
      url = "git+https://github.com/hercules-ci/flake-parts?ref=main";
      inputs.nixpkgs-lib.follows = "nixpkgs";
    };
    import-tree.url = "git+https://github.com/vic/import-tree?ref=main";

    # Banking and brokerage CLIs, built from their pinned release sources with
    # this flake's nixpkgs (modules/mercury, modules/public).
    # Declared disk layouts (modules/hetzner/host.nix).
    disko = {
      url = "git+https://github.com/nix-community/disko?ref=refs/tags/v1.13.0";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # REA, reverse engineering for agents (modules/rea): the digital twin of
    # whatever a browser flow drives.
    rea = {
      url = "git+https://github.com/morluto/rea?ref=refs/tags/rea-agents-6.7.0";
      flake = false;
    };
    # Built from source to carry ./modules/proton/_patches (modules/proton/tools.nix).
    secretspec-src = {
      url = "git+https://github.com/cachix/secretspec?ref=refs/tags/v0.21.1";
      flake = false;
    };
    mercury-cli = {
      url = "git+https://github.com/MercuryTechnologies/mercury-cli?ref=refs/tags/v0.11.8";
      flake = false;
    };
    publicdotcom-cli = {
      url = "git+https://github.com/PublicDotCom/publicdotcom-cli?ref=refs/tags/v1.3.7";
      flake = false;
    };

    # Agent personas for the Orca swarms (modules/governance), MIT; pinned
    # to a commit since the repository has no releases.
    agency-agents = {
      url = "git+https://github.com/msitarzewski/agency-agents?ref=main&rev=4e3ac3ca6604c75113f52c695dbddcc7af928b46";
      flake = false;
    };

    # Typed declarations: refinement and dependent types checked at eval time.
    nix-effects = {
      url = "git+https://github.com/kleisli-io/nix-effects?ref=refs/tags/v0.16.0";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.nix-unit.follows = "";
    };
  };

  # Prebuilt kernel/firmware; avoids compiling the Pi kernel yourself.
  nixConfig = {
    extra-substituters = [ "https://nixos-raspberrypi.cachix.org" ];
    extra-trusted-public-keys = [
      "nixos-raspberrypi.cachix.org-1:4iMO9LXa8BqhU+Rpg6LQKiGa2lsNh/j2oiYLNOQ5sPI="
    ];
  };

  outputs = inputs: inputs.flake-parts.lib.mkFlake { inherit inputs; } (inputs.import-tree ./modules);
}
