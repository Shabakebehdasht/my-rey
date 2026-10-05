---
name: hermes-plugin-install
description: Install and verify plugins from external Git repos.
version: 1.0.0
author: Hermes Agent
license: MIT
platforms: [linux, macos, windows]
metadata:
  hermes:
    tags: [hermes, plugins, install, security-scan]
    related_skills: [read-the-damn-docs]
---

# Installing Hermes plugins from external repos

## When to Use

- The user asks to install a plugin/skill pack from a GitHub repo or any
  source outside the Hermes catalog ("install <repo>", "add superpowers").
- An install is blocked by the security scan and the user must decide whether
  to override — load `references/security-scans.md` for the triage rules.
- Post-install sanity: confirming a plugin is enabled, its skills registered,
  or diagnosing why its skills are not triggering yet.

## Procedure

1. **Read the repo's own install docs first — never guess the CLI syntax.**
   Fetch the README and locate the section for *this* harness (e.g. a
   "Hermes Agent" heading). Multi-harness repos (Claude Code, Codex, Cursor,
   Hermes, …) document a different command per harness; copying another
   harness's section installs to the wrong location or does nothing.
2. **Install:** `hermes plugins install <owner>/<repo> --enable`
   The `custom (unreviewed) source — not from the Hermes catalog` warning is
   expected, not an error.
3. **If the security scan blocks the install** (verdict `BLOCKED`, "use
   --force to override"): triage the findings yourself first
   (`references/security-scans.md`), then give the user a two-line summary of
   what the flags actually are and ask for approval before `--force`. Never
   override silently, and never present a scan as a certification.
4. **Re-run install once to resolve install-time notices.** The installer may
   say `Skipped Node deps — run ... again to retry` or warn about a missing
   `plugin.yaml`. Re-run once; if the second run repeats the same message it
   is cosmetic — check `package.json` `dependencies` (often empty, so no deps
   were actually skipped) and `.hermes-plugin/plugin.yaml` (present even when
   the top-level warning fires).
5. **Verify — three checks, all cheap:**
   - `hermes plugins list | grep -i <name>` → `enabled`, expected version, source.
   - `skills_list` → plugin skills appear with the `<plugin>:` prefix under
     category `plugin`. Their descriptions are often empty; read the SKILL.md
     under `<plugin-dir>/skills/<name>/SKILL.md` if you need trigger text.
   - The plugin dir's `.hermes-plugin/plugin.yaml` → `provides_hooks` tells you
     what runs at session time (e.g. `pre_llm_call` for a bootstrap).
6. **Report activation scope.** The gateway reloads plugins live, but skill
   *bootstrap* lands in the next session start; Hermes has no post-compaction
   hook, so a long session that compacts early loses it — tell the user to
   start a fresh session if skills stop triggering.

## Pitfalls

- **`clarify()` choices are a plain JSON array of strings.** Passing objects
  (`{label, description}`) is rejected by schema validation; put the
  recommendation text inside the string, "(Recommended)" suffix and all.
- **Do not re-run install in a loop** chasing a notice that repeats verbatim —
  two identical runs means the message is informational; move to verification.
- **Never hardcode or assume the plugin's manifest layout.** Some repos ship
  `.hermes-plugin/plugin.yaml`; others rely on a top-level `plugin.json` or
  `__init__.py`. Check the directory, then conclude.
- **Duplicate skill names are fine.** A plugin skill with the same bare name as
  a local skill is namespaced `<plugin>:<name>` and does not shadow the local
  one; mention the prefix when telling the user which to load.
