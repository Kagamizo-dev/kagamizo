# reverse-engineering: the model registry

Read CLAUDE.md first. Kind: reverse-engineering.

The owner's direction of 2026-11-06: choose the best open weights and harness for each task, at the lowest precision that does it.
- `agents.models.<task>` = { modality (an enum: text, code, image-in, image-out, audio-in, audio-out, video-in, video-out); weights (a Hugging Face repo, revision and file, hash-pinned); quantization; licence (read from the repo); harness; host (an enum: tier1-cpu, serverless-gpu, openrouter); evaluation (the benchmark and score we measured) }.
- Lean: every task's tier is the cheapest that meets its declared score. A model on the host fits the host's memory. Closed weights are never pinned.
- Start from the tasks that exist (tiers.nix), and add video and audio once a GPU host is declared.
