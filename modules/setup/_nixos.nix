# First-run setup wizard, shown after the welcome screen in the first terminal:
#   1. internet (phone USB tethering, no password baked into the image)
#   2. Proton Pass sign-in (pass-cli)
#   3. Wi-Fi networks from Proton Pass   (vault `yoga`, Login items "Wi-Fi: <network>")
#   4. OpenRouter key from Proton Pass   (vault `yoga`, Login item "OpenRouter")
#      -> two Pi coding agents in tmux windows agent-1 and agent-2
# Secrets only ever live in memory (tmux's environment, NetworkManager); nothing is
# written to the USB stick. Run `setup` again at any time.
{ pkgs, ... }:
let
  vault = "yoga";
  model = "deepseek/deepseek-v4-flash";

  setup = pkgs.writeShellApplication {
    name = "setup";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.curl
      pkgs.jq
      pkgs.networkmanager
      pkgs.pi-coding-agent
      pkgs.proton-pass-cli
      pkgs.tmux
    ];
    text = ''
      VAULT=${vault}
      MODEL=${model}

      say()  { printf '\n\033[1;35m%s\033[0m\n' "$1"; }
      ok()   { printf '  \033[32m✓\033[0m %s\n' "$1"; }
      warn() { printf '  \033[33m!\033[0m %s\n' "$1"; }
      online() { curl -fsS --max-time 5 -o /dev/null https://account.proton.me; }

      say "Step 1 of 4: Internet"
      until online; do
        warn "Not online yet."
        echo "    Plug your phone in with a USB cable and turn on USB tethering"
        echo "    (Settings > Network & internet > Hotspot & tethering > USB tethering)."
        echo "    Checking again in 10 s. Type w and Enter to pick a Wi-Fi network by hand."
        answer=""
        read -r -t 10 answer || true
        if [ "$answer" = "w" ]; then nmtui-connect || true; fi
      done
      ok "Online"

      say "Step 2 of 4: Proton Pass"
      until pass-cli test > /dev/null 2>&1; do
        echo "    Sign in to Proton Pass. A link will appear: open it on your phone."
        pass-cli login || true
      done
      ok "Signed in to Proton Pass"

      say "Step 3 of 4: Wi-Fi networks from Proton Pass"
      titles=$(pass-cli item list "$VAULT" --output json 2> /dev/null \
        | jq -r '[.. | objects | .title? | strings | select(startswith("Wi-Fi: "))] | unique[]' \
        || true)
      if [ -z "$titles" ]; then
        warn "No 'Wi-Fi: <network>' items in vault '$VAULT'. Keep the phone plugged in, or run nmtui."
      else
        while IFS= read -r title; do
          ssid=''${title#"Wi-Fi: "}
          if psk=$(pass-cli item view --vault-name "$VAULT" --item-title "$title" --field password 2> /dev/null) \
            && [ -n "$psk" ]; then
            nmcli connection delete id "$ssid" > /dev/null 2>&1 || true
            if nmcli connection add type wifi con-name "$ssid" ssid "$ssid" \
              wifi-sec.key-mgmt wpa-psk wifi-sec.psk "$psk" > /dev/null; then
              ok "Saved Wi-Fi '$ssid' (connects automatically when in range)"
            else
              warn "Could not save Wi-Fi '$ssid'"
            fi
          else
            warn "Could not read the password for '$title'"
          fi
        done <<< "$titles"
        echo "    Once Wi-Fi is connected you can unplug the phone."
      fi

      say "Step 4 of 4: OpenRouter and the coding agents"
      if key=$(pass-cli item view --vault-name "$VAULT" --item-title OpenRouter --field password 2> /dev/null) \
        && [ -n "$key" ]; then
        ok "OpenRouter key loaded (memory only)"
        if [ -n "''${TMUX:-}" ]; then
          tmux set-environment -g OPENROUTER_API_KEY "$key"
          for n in 1 2; do
            tmux kill-window -t "agent-$n" 2> /dev/null || true
            tmux new-window -d -n "agent-$n" "pi --provider openrouter --model $MODEL; exec bash"
          done
          ok "Two Pi agents running $MODEL: click agent-1 / agent-2 in the tmux bar (or Ctrl-a 2, Ctrl-a 3)"
        else
          warn "Not inside tmux: start one with  OPENROUTER_API_KEY=... pi --provider openrouter --model $MODEL"
        fi
      else
        warn "No 'OpenRouter' item in vault '$VAULT' (a Login item with the API key as its password)."
      fi

      say "Setup finished. Run 'setup' again any time."
    '';
  };
in
{
  environment.systemPackages = [
    setup
    pkgs.pi-coding-agent
  ];
}
