{ ... }:
{
  programs.tmux = {
    enable = true;
    terminal = "tmux-256color";
    keyMode = "vi";
    escapeTime = 10;
    historyLimit = 50000;
    baseIndex = 1;
    clock24 = true;
    extraConfig = ''
      set -g mouse on
      set -g renumber-windows on
      bind | split-window -h -c "#{pane_current_path}"
      bind - split-window -v -c "#{pane_current_path}"
      bind r source-file /etc/tmux.conf \; display "reloaded"
    '';
  };
}
