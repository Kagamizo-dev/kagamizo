# The media pipeline on jingzo-host (../media): the indexer over what
# arrives, and the renderer on demand. The whisper model is pinned by hash
# and fetched at build, so it lives in the cache CI fills, never downloaded
# on the host.
#
#   media-index.service    catalogs every clip under <incoming>/<date>/ not
#                          yet in <catalog>; started when a date folder
#                          appears and every 15 minutes (the sync hop drops
#                          files into a folder after making it)
#   media-render@NAME      renders <cuts>/NAME.json to <renders>/NAME.mp4,
#                          refusing a cut list the rule rejects
{
  mediaIndex,
  mediaRender,
  whisperModel, # media.whisperModel
  incoming,
  catalog,
  cuts,
  renders,
}:
{ pkgs, ... }:
let
  model = pkgs.fetchurl {
    url = "https://huggingface.co/${whisperModel.repo}/resolve/main/${whisperModel.file}";
    inherit (whisperModel) sha256;
  };
  dirs = [
    incoming
    catalog
    cuts
    renders
  ];
in
{
  users = {
    users.media = {
      isSystemUser = true;
      group = "media";
      home = "/var/lib/media";
    };
    groups.media = { };
  };

  systemd = {
    tmpfiles.rules = [
      "d /var/lib/media 0750 media media -"
    ]
    ++ map (d: "d ${d} 0750 media media -") dirs;

    services = {
      media-index = {
        description = "Catalog the clips that arrived";
        after = [ "systemd-tmpfiles-setup.service" ];
        serviceConfig = {
          Type = "oneshot";
          User = "media";
          Group = "media";
          # Whisper small on two of the four cores, behind everything else.
          Nice = 15;
          MemoryMax = "3G";
          ExecStart = "${pkgs.lib.getExe mediaIndex} --incoming ${incoming} --catalog ${catalog} --whisper-model ${model} --threads 2";
        };
      };

      "media-render@" = {
        description = "Render the cut list %I";
        serviceConfig = {
          Type = "oneshot";
          User = "media";
          Group = "media";
          Nice = 10;
          ExecStart = "${pkgs.lib.getExe mediaRender} ${cuts}/%I.json --catalog ${catalog} --incoming ${incoming} --out ${renders}/%I.mp4";
        };
      };
    };

    paths.media-index = {
      description = "A new day's folder of footage";
      wantedBy = [ "multi-user.target" ];
      pathConfig = {
        PathChanged = incoming;
        MakeDirectory = true;
      };
    };

    timers.media-index = {
      description = "Catalog what arrived since";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnBootSec = "5min";
        OnUnitActiveSec = "15min";
        RandomizedDelaySec = "1min";
      };
    };
  };
}
