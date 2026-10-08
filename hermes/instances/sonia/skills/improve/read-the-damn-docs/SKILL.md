---
name: read-the-damn-docs
description: "Read docs before assuming. Use for APIs, frameworks, CLIs."
version: 1.0.0
author: BuilderIO
license: MIT
metadata:
  hermes:
    tags: [docs, research, api, frameworks]
    category: improve
  source: https://github.com/BuilderIO/skills
---

# Read The Damn Docs

Do not guess where authoritative docs can answer the question. The most common
right move is to web-search for the current official docs, open the relevant
pages, and read them before coding.

## Docs-First Triggers

Read docs before proceeding when any of these are true:

- The user asks for "latest", "current", "official", "supported", "best
  practice", "recommended", "today", "now", or "look it up".
- The needed docs are not already in the repo or supplied by the user.
- The task adds, upgrades, configures, or imports a package, SDK, framework,
  plugin, CLI, model, cloud resource, or provider integration.
- The API is fast-moving or version-sensitive.
- The implementation depends on auth, OAuth scopes, permissions, secrets,
  webhooks, billing, payments, PII, encryption, data retention, migrations,
  retries, rate limits, quotas, caching, deploys, or compliance.
- An error mentions deprecation, unknown options, missing exports, invalid
  config, unsupported fields, changed defaults, or version mismatch.
- A repo has local docs, ADRs, generated schemas, OpenAPI specs, route/action
  registries, design-system docs, or package-level READMEs.
- The choice is expensive to reverse.
- You catch yourself about to write "usually", "probably", "I think", "from
  memory", or code copied from model memory for an external API.

## Required Workflow

1. Identify the exact surface: package name, installed version, target version,
   provider endpoint, CLI command, config file, local helper, schema, or
   product feature.
2. Search the web for the current official docs unless the relevant docs are
   already local or the user supplied a URL.
3. Open and read the docs closest to that surface.
4. Extract the few facts needed: option names, imports, lifecycle rules,
   default behavior, breaking changes, limits, permissions, examples.
5. Implement or answer using those facts. If the docs conflict with existing
   code, inspect the local code path and call out the discrepancy.
6. Verify with the smallest useful check.
7. In the final answer, name the docs or local files consulted.

## When A Quick Local Read Is Enough

Do not browse the web for every tiny edit. A docs pass can be local and brief
when the answer is already in the repo. But if the task depends on an external
tool, package, provider, or current product behavior, web search is usually
the right first step.

## If Docs Are Unavailable

If network access, auth, or missing local files prevents reading the docs, say
that plainly before relying on memory.