---
name: read-the-damn-docs
description: "Read official docs before coding. Avoids outdated patterns."
version: 1.0.0
author: BuilderIO
license: MIT
metadata:
  hermes:
    tags: [docs, documentation, coding, best-practices]
    source: https://github.com/BuilderIO/skills
---

# Read The Damn Docs

## When to Use

Use this skill before any coding task that involves a specific framework, library, API, or tool whose behavior may have changed or whose conventions you're unsure about. Especially critical when working with versioned technologies (Laravel, React, etc.) or when the codebase has multiple dependencies.

Do not guess where authoritative docs can answer the question. The most common right move is to web-search for the current official docs, open the relevant pages, and read them before coding. For APIs, versions, provider behavior, config, limits, lifecycle hooks, or security-sensitive flows, ground the answer in what the docs actually say.

## Workflow

1. Identify what technology/framework/library the task involves.
2. Search for the **current official documentation** — prefer official sites over blog posts or third-party summaries.
3. Read the relevant documentation pages:
   - For APIs: read endpoint docs, auth, rate limits, error codes.
   - For frameworks: read configuration, conventions, migration guides.
   - For libraries: read API surface, version compatibility, breaking changes.
   - For tools: read CLI flags, config file format, environment variables.
4. Extract the few facts needed for the task: option names, imports, lifecycle rules, default behavior, breaking changes, limits, permissions, and examples for the current major version.
5. Apply those facts in the implementation.

## Priority

Internal project docs (AGENTS.md, CLAUDE.md, README, ADRs) → internal code, then official upstream docs. For new packages, verify the latest version before writing imports, config, or install commands.

## When A Quick Local Read Is Enough

Do not browse the web for every tiny edit. A docs pass can be local and brief when:
- The change is well inside an established pattern in the same repo.
- The affected code has adjacent examples and the API surface is obvious.
- You already read the relevant docs in this session and they are still current.

## Common Pitfalls

- Using deprecated APIs because you remembered the old docs.
- Assuming default behavior changed between versions.
- Missing required config or security settings.
- Using wrong import paths after a major version refactor.
- Ignoring breaking changes in newer versions.
