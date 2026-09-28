---
name: github-discussions
description: "GitHub Discussions via gh/GraphQL. No REST, no view/edit."
version: 1.0.0
author: Hermes Agent (session-derived)
license: MIT
metadata:
  hermes:
    tags: [github, discussions, graphql, gh, publishing]
    category: software-development
    related_skills: [improve-workflows, github]
---

# GitHub Discussions

## When to Use

- A user gives a `github.com/OWNER/REPO/discussions/...` URL, or asks to post,
  reply to, or read a discussion.
- Publishing a proposal or status note to a repo that uses Discussions where
  other repos would use issues.
- Replying to several active threads with your own analysis.

Not for issues or PRs — the bundled `github` skill covers those.

Discussions exist ONLY in the GraphQL API. There is no REST endpoint, and
`gh` has no `discussion view` / `edit` / `delete` subcommand — only
`gh discussion list` and `gh discussion create`. Everything else is
`gh api graphql`.

The bundled `github` skill covers issues and PRs; it does not cover
discussions. Do not go looking there for this.

## Preflight

Discussions need the `write:discussion` (or `repo`) token scope. Check before
writing, because a missing scope surfaces as a permissions error mid-batch:

```bash
gh auth status
```

`gh auth status` also lists every account and which one is active. Publishing
goes out as the ACTIVE account — that is often a bot or shared account, not the
person who asked. Say which account will be used before publishing.

## Read before writing

```bash
# List: always --json when you will act on the result
gh discussion list -R owner/repo --limit 30 \
  --json number,title,category,createdAt,url,author
```

```bash
# Read body + capture the node id (comments need the id, not the number)
gh api graphql -f query='
query{repository(owner:"OWNER",name:"REPO"){
  d:discussion(number:N){
    id title createdAt author{login} body
    category{name slug}
  }}}'
```

Read the body before replying. A reply written without reading the parent
answers a question it never saw, and that is public.

## Create

```bash
gh discussion create -R owner/repo \
  --category "Ideas" \
  --title 'TITLE' \
  --body-file /tmp/body.md
```

- `--body-file` is mandatory for non-ASCII and multi-line bodies. `-b` takes one
  shell argument; Persian/RTL text plus newlines through `-b` gets mangled by
  quoting or collapses into a single paragraph.
- `--category` must match an existing category name exactly:
  ```bash
  gh api graphql -f query='
  query{repository(owner:"OWNER",name:"REPO"){
    discussionCategories{nodes{name slug}}}}'
  ```
- Sweep for duplicates first (`gh discussion list --json title`) — a duplicate
  post is harder to clean up than a slow search.

The command prints the new discussion URL. That URL is the verification
handle: report it verbatim, never report "posted" without it.

## Comment

Needs the **node id** (`D_kwDOOLHV784...`), not the discussion number. Passing
the number as `id` gives a type/null error.

```bash
gh api graphql \
  -f query='mutation($id:ID!,$b:String!){
    addDiscussionComment(input:{discussionId:$id, body:$b}){
      comment{url}}}}' \
  -f id='D_kwDOOLHV784...' \
  -F b=@/tmp/comment.md
```

`-F b=@path` reads the body from a file (same reason as `--body-file`).
`-f b=...` would send the literal string `@/tmp/comment.md`.

## Batching many writes

Fan out to many discussions in ONE batched call — a script that loops inside a
single `execute_code` invocation, not one tool call per discussion. A per-item
call asks the user to approve N external writes, and when approval does not
arrive in time the run is abandoned partway, leaving a half-published set with
no record of which items landed.

Keep every body written to disk first, so a blocked or timed-out run can be
resumed by re-publishing the files without redoing the analysis.

If a batch is interrupted anyway, report per-target status honestly: which URLs
were written, which were not, and where the unwritten bodies sit. Partial
success reported as full success is worse than no report.

## Verify every number before publishing

Issue and PR numbers cited in a body must be checked against
`gh issue list --state all` first. A number recalled from a summary can be off
by a large margin. It is a public error once posted, and nobody in-thread
necessarily catches it.

## Content pitfall: critique, don't flatter

When adding your own view to someone else's discussion thread, the value is in
what they did not already say. Write points they cannot derive from their own
post:

- name the concrete risk with a mechanism ("error path is silent", "state lives
  in a component property, so the download would not match what the user sees")
- flag the specific decision that will be expensive to reverse
- give a size/priority ordering, not an undifferentiated wishlist

A comment that only restates the thread in agreeable words is noise and reads as
padding.
