User prefers to call the assistant "ریحانه" (Reyhane) instead of Hermes.
§
On this box origin = Shabakebehdasht/h-dashboard
§
User profile
§ Wants progress visibility on long multi-step work: an initial full status report, then a terse status every 5 minutes until the task finishes (Persian, labelled sections, no filler). Reports should stop as soon as the work is complete.
§
User commands
Peer agents kimya / sevda / sonia / kylie / rebecca all live in ONE repo: Shabakebehdasht/my-rey (default branch is `reyhane`, the only branch), with the same-named workflows. The per-peer repos my-kim / my-sev / my-son / my-kyl no longer exist (GitHub 404). To wake one: scripts/peer-wake.sh <peer> in the hermes-peer-agents skill (checks state first, skips if already booting/awake, fail-closed). Then to send work: hermes peer dm <peer> "<message>". "بچه ها رو بیدار کن" / "wake the kids" means wake all five. HARD RULE: never power a peer machine on twice — never run a bare `gh workflow run` for a peer; every workflow already has a `concurrency: cancel-in-progress: false` guard, and all five peer workflows live in the same repo.
