{
  description = "NixOS images and the Kagamizo identity (Cloudflare, Proton Pass) as code";

  # Pinned by flake.lock. Upstream follows the stable nixos-26.05 channel, so
  # the base only moves when `nix flake update` is run on purpose.
  inputs = {
    nixos-raspberrypi.url = "git+https://github.com/nvmd/nixos-raspberrypi?ref=main";
    # The images' nixpkgs, shared by everything else in the flake.
    nixpkgs.follows = "nixos-raspberrypi/nixpkgs";

    # Dendritic layout: every file under ./parts is a flake-parts module.
    flake-parts = {
      url = "git+https://github.com/hercules-ci/flake-parts?ref=main";
      inputs.nixpkgs-lib.follows = "nixpkgs";
    };
    import-tree.url = "git+https://github.com/vic/import-tree?ref=main";

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

  outputs = inputs: inputs.flake-parts.lib.mkFlake { inherit inputs; } (inputs.import-tree ./parts);
}
