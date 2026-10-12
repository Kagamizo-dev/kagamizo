# CLI tools shared by the desktop image.
{ pkgs, ... }:
{
  environment.systemPackages = with pkgs; [
    git
    vim
    htop
    proton-pass-cli # `pass-cli login` prints a URL you can open on your phone
  ];
}
