{ pkgs, ... }:
let
  # Fuzzy-searchable cheat sheet of every key binding that has a note
  # (all of tmux's defaults have notes, and so do ours). Opened with `prefix ?`.
  keysFinder = pkgs.writeShellApplication {
    name = "tmux-keys";
    runtimeInputs = [
      pkgs.tmux
      pkgs.fzf
      pkgs.gnused
    ];
    text = ''
      {
        tmux list-keys -N -T prefix
        tmux list-keys -N -T root      | sed 's/^/(no prefix) /'
        tmux list-keys -N -T copy-mode-vi | sed 's/^/(copy mode)  /'
      } | fzf --reverse --no-sort --ansi \
              --prompt 'key > ' \
              --header 'Type to filter. Prefix is Ctrl-a. Esc to close.' \
        || true
    '';
  };
in
{
  programs.tmux = {
    enable = true;
    shortcut = "a"; # prefix = Ctrl-a (Ctrl-a Ctrl-a / Ctrl-a a sends a literal Ctrl-a)
    terminal = "tmux-256color";
    keyMode = "vi";
    escapeTime = 10;
    historyLimit = 50000;
    baseIndex = 1;
    clock24 = true;
    extraConfig = ''
      set -g mouse on
      set -g renumber-windows on
      set -g set-clipboard on
      set -g focus-events on
      setw -g pane-base-index 1
      setw -g automatic-rename on

      # ---- status bar: shows when the prefix is active ----
      set -g status-style "bg=colour236,fg=colour250"
      set -g status-left  "#[bold] #S #[default]#{?client_prefix,#[bg=colour208 fg=black bold] PREFIX #[default],} "
      set -g status-right "#[fg=colour245]? = key finder  Space = menu  #[default] %H:%M "
      set -g window-status-current-style "bg=colour33,fg=white,bold"

      # ---- discoverability ----
      bind -N "Search all key bindings (fuzzy)" ? display-popup -E -w 85% -h 85% -T " tmux keys " ${keysFinder}/bin/tmux-keys
      bind -N "Search all key bindings (fuzzy)" / display-popup -E -w 85% -h 85% -T " tmux keys " ${keysFinder}/bin/tmux-keys

      bind -N "Quick menu (which-key style)" Space display-menu -T "#[align=centre] tmux " -x C -y C \
        "Search every key"      "?" "display-popup -E -w 85% -h 85% -T ' tmux keys ' ${keysFinder}/bin/tmux-keys" \
        "" \
        "-#[nodim,bold]Windows"  ""  "" \
        "  New window"          c   "new-window -c '#{pane_current_path}'" \
        "  Rename window"       ,   "command-prompt -I '#W' 'rename-window -- \"%%\"'" \
        "  Pick window"         w   "choose-tree -Zw" \
        "  Close window"        X   "confirm-before -p 'kill window #W? (y/n)' kill-window" \
        "" \
        "-#[nodim,bold]Panes"    ""  "" \
        "  Split right"         |   "split-window -h -c '#{pane_current_path}'" \
        "  Split down"          -   "split-window -v -c '#{pane_current_path}'" \
        "  Zoom pane"           z   "resize-pane -Z" \
        "  Close pane"          x   "confirm-before -p 'kill pane? (y/n)' kill-pane" \
        "" \
        "-#[nodim,bold]Sessions" ""  "" \
        "  Pick session"        s   "choose-tree -Zs" \
        "  New session"         S   "command-prompt -p 'new session name:' 'new-session -s \"%%\"'" \
        "  Detach"              d   "detach-client" \
        "" \
        "Reload config"         r   "source-file /etc/tmux.conf ; display 'reloaded'"

      # ---- windows ----
      bind -N "New window (same directory)"   c new-window -c "#{pane_current_path}"
      bind -N "Next window (no prefix: Shift-Right)"     -n S-Right next-window
      bind -N "Previous window (no prefix: Shift-Left)"  -n S-Left  previous-window
      bind -N "Close window (asks first)"     X confirm-before -p "kill window #W? (y/n)" kill-window

      # ---- panes ----
      bind -N "Split side-by-side (same directory)" | split-window -h -c "#{pane_current_path}"
      bind -N "Split top/bottom (same directory)"   - split-window -v -c "#{pane_current_path}"
      bind -N "Focus pane left"  h select-pane -L
      bind -N "Focus pane down"  j select-pane -D
      bind -N "Focus pane up"    k select-pane -U
      bind -N "Focus pane right" l select-pane -R
      bind -N "Focus pane (no prefix: Alt-arrows)" -n M-Left  select-pane -L
      bind -N "Focus pane (no prefix: Alt-arrows)" -n M-Down  select-pane -D
      bind -N "Focus pane (no prefix: Alt-arrows)" -n M-Up    select-pane -U
      bind -N "Focus pane (no prefix: Alt-arrows)" -n M-Right select-pane -R
      bind -N "Resize pane left (repeatable)"  -r H resize-pane -L 5
      bind -N "Resize pane down (repeatable)"  -r J resize-pane -D 5
      bind -N "Resize pane up (repeatable)"    -r K resize-pane -U 5
      bind -N "Resize pane right (repeatable)" -r L resize-pane -R 5
      bind -N "Cycle pane layouts" = next-layout

      # ---- misc ----
      bind -N "Reload tmux config" r source-file /etc/tmux.conf \; display "tmux config reloaded"

      # ---- copy mode (vi keys) ----
      bind -N "Enter copy mode (scroll/search/select)" Enter copy-mode
      bind -T copy-mode-vi -N "Start selection" v send -X begin-selection
      bind -T copy-mode-vi -N "Toggle rectangle selection" C-v send -X rectangle-toggle
      bind -T copy-mode-vi -N "Copy selection and leave copy mode" y send -X copy-selection-and-cancel
    '';
  };

  environment.systemPackages = [
    keysFinder
    pkgs.fzf
  ];
}
