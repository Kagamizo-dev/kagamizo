# Tier 1 on jingzo-host (../agents/tiers.nix): a small quantized model on
# the CPU, served by llama.cpp on the loopback as an OpenAI-compatible
# endpoint. Free, so classification, extraction, tagging and triage never
# reach a paid key. The model file is pinned by hash and fetched at build
# (so it lives in the cache CI fills, not downloaded on the host).
#
#   http://127.0.0.1:<port>/v1   (Open WebUI lists it beside OpenRouter;
#                                 the coordinator routes rank-1 tasks to it)
{
  model, # agents.models.<name>
  name,
  port,
}:
{ pkgs, ... }:
let
  gguf = pkgs.fetchurl {
    url = "https://huggingface.co/${model.repo}/resolve/main/${model.file}";
    inherit (model) sha256;
  };
in
{
  services.llama-cpp = {
    enable = true;
    host = "127.0.0.1";
    inherit port;
    model = "${gguf}";
    extraFlags = [
      "--alias"
      name
      # Two of the four cores, leaving the rest to the agents; a modest
      # context keeps memory near the file's size.
      "--threads"
      "2"
      "--ctx-size"
      "8192"
      "--parallel"
      "2"
      "--no-webui"
    ];
  };
  systemd.services.llama-cpp.serviceConfig = {
    # No one on the host but its agents needs it, and never over the network.
    MemoryMax = "4G";
    Nice = 10;
  };
}
