# Welcome screen shown in the first terminal: a fastfetch summary, a few soft
# system checks (they only report, they never fail), and the keys you need.
{ pkgs, ... }:
let
  welcome = pkgs.writeShellApplication {
    name = "welcome";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.fastfetch
      pkgs.networkmanager
      pkgs.wireplumber
    ];
    text = ''
      ok()  { printf '  \033[32m✓\033[0m %s\n' "$1"; }
      bad() { printf '  \033[33m✗\033[0m %s\n' "$1"; }

      # Plain escape code: `clear` fails without a terminal, and this screen must never abort.
      if [ -t 1 ]; then printf '\033[H\033[2J'; fi
      fastfetch --config ${./welcome/fastfetch.jsonc} || echo "(system summary unavailable)"

      printf '\n\033[1;35m System check\033[0m\n'

      if [ "$(timeout 3 nmcli -t -f STATE general 2>/dev/null || true)" = "connected" ]; then
        ok "Online"
      elif timeout 3 nmcli -t -f TYPE device 2>/dev/null | grep -q wifi; then
        bad "Wi-Fi adapter found but not connected: run nmtui"
      else
        bad "No Wi-Fi adapter detected"
      fi

      found_battery=0
      for b in /sys/class/power_supply/BAT*; do
        [ -e "$b" ] || continue
        found_battery=1
        ok "Battery $(cat "$b/capacity")% ($(cat "$b/status"))"
      done
      [ "$found_battery" = 1 ] || bad "No battery detected"

      if timeout 3 wpctl inspect @DEFAULT_AUDIO_SINK@ >/dev/null 2>&1; then
        ok "Audio output ready"
      else
        bad "No audio output found"
      fi

      if ls /dev/dri/card* >/dev/null 2>&1; then
        ok "Graphics ready"
      else
        bad "No graphics device found"
      fi

      printf '\n\033[1;35m Quick keys\033[0m\n'
      cat ${./welcome/keys.txt}
      echo
    '';
  };
in
{
  environment.systemPackages = [ welcome ];
}
