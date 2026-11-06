# twin: one bot per team

Read CLAUDE.md first. Kind: world.

Azalea is adopted (`twin.adoptions.azalea`, azalea-rs/azalea at 0d38e0dc, MIT, protocol 26.2). Its protocol must match the server's (Pumpkin 26.3) before bots connect. Pin an Azalea commit that speaks 26.3, or record the mismatch in the adoption and wait.

Each dsh team gets a bot named after it that stands in its room.
- Its status comes from the harness: working, idle or reviewing.
- It shows the team's last message and spend as a sign or nameplate.

A Rust crate `modules/twin/_bots` holds them, run on the host as a service.
