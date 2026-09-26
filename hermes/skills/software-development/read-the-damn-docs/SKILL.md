---
name: read-the-damn-docs
description: >-
 Use when implementing, integrating, upgrading, debugging, or answering
 anything involving third-party APIs, libraries, frameworks, CLIs, cloud
 services, model/provider SDKs, fast-moving product behavior, user requests for
 latest/current/official behavior, unfamiliar repo docs/specs, errors that may
 indicate API drift, or high-stakes auth, security, billing, data, migration,
 deployment, compliance, or privacy behavior. Forces web-search for
 current official docs and read primary docs before assuming from memory.
tags: [docs, documentation, coding, best-practices]
version: 1.1.0
author: BuilderIO
source: https://github.com/BuilderIO/skills
---

# Read The Damn Docs

Do not guess where authoritative docs can answer the question. The most common
right move is to web-search for the current official docs, open the relevant
pages, and read them before coding. For APIs, versions, provider behavior,
config, limits, lifecycle hooks, or security-sensitive flows, ground the answer
in what the docs actually say.

## Docs-First Triggers

Read docs before proceeding when any of these are true:

- The user asks for "latest", "current", "official", "supported", "best
 practice", "recommended", "today", "now", or "look it up".
- The needed docs are not already in the repo or supplied by the user. Search
 the web for the official docs rather than hoping model memory is current.
- The task adds, upgrades, configures, or imports a package, SDK, framework,
 plugin, CLI, model, cloud resource, or provider integration.
- The API is fast-moving or version-sensitive: AI SDKs, OpenAI/Anthropic/Google
 APIs, Next.js, React, Tailwind, Vite, Nitro, Drizzle, Prisma, Stripe, GitHub,
 Slack, Notion, browser APIs, deployment platforms, auth libraries, and similar.
- The implementation depends on auth, OAuth scopes, permissions, secrets,
 webhooks, billing, payments, PII, encryption, data retention, migrations,
 retries, rate limits, quotas, caching, deploys, or compliance.
- An error mentions deprecation, unknown options, missing exports, invalid
 config, unsupported fields, changed defaults, or version mismatch.
- A repo has local docs, ADRs, generated schemas, OpenAPI specs, route/action
 registries, design-system docs, or package-level READMEs that could define the
 contract.
- The choice is expensive to reverse: public wire formats, database schema,
 migration strategy, persistent IDs, event names, customer-visible behavior, or
 external automation contracts.
- You catch yourself about to write "usually", "probably", "I think", "from
 memory", or code copied from model memory for an external API.

## What Counts As Docs

Use the most authoritative source available:

- Local repo docs, specs, ADRs, schemas, generated types, package READMEs, and
 tests for project-specific behavior.
- Official product docs, API references, migration guides, changelogs, release
 notes, and SDK source/types for third-party behavior. Find these with web
 search when you do not already have the exact URL.
- Package registry metadata for versions. Before adding a dependency, verify the
 latest version and check for breaking changes.

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