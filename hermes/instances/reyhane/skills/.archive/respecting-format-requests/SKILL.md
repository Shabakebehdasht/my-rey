---
name: respecting-format-requests
description: "Use when the user dictates an answer's shape."
version: 1.0.0
author: curator
license: MIT
metadata:
  hermes:
    tags: [format, communication, brevity, yes-no, constraints]
    category: communication
---

# Respecting Format Requests

When the user specifies the shape of the answer, the shape is a hard specification,
not a hint. Deliver exactly that shape FIRST; everything else waits for a follow-up.

## When to Use

- "Answer in one word." / "Just yes or no." / "Nothing else."
- "Only give me the command." / "List only the file names."
- "Say it exactly like this." / "No explanation."
- Any turn where the user restates a formatting constraint you already broke once.

## Standing Rules

- An explicit format instruction outranks the default habit of explaining context,
  listing evidence, or offering next steps.
- Mirror the user's language in the reply. Keep commands, paths, identifiers, error
  strings, and filenames verbatim in their original form.
- No unsolicited offers at the end ("want me to also check X?"). An offer is extra
  text the user did not ask for, and it reads as ignoring the constraint.

## Pitfalls

### Answering the shape, then adding sections, is still not following the shape

Leading with the requested answer and then appending caveats, verification output, or
a "however" paragraph fails the request just as badly as ignoring it. If the user said
one word, the reply is one word — even when there is a genuine nuance behind it.
Deliver the nuance only when asked, or in a separate turn if the format allows.

### Verification habits do not license format expansion

Gathering evidence is right; narrating it is not, when the format forbids it. Check
the facts, then answer in the requested shape. The user cannot see your tool calls,
so a verified answer can be one word.

### Confusion between "answer briefly" and "answer in a specific shape"

"Short" is a length hint you can apply while still being useful. "One word", "only
the list", "just the command", "in exactly these words" are shapes — reproduce them
literally, in the requested order.

### When the format and a needed warning collide

A genuinely important caveat — a security problem, an irreversible or destructive
action, a multi-step sequence where misreading causes damage — still gets stated,
but AFTER the requested answer and in as few lines as possible. Do not bury it; do
not expand the whole reply around it.

## Verification

Before sending, check the reply against the request literally:

- Does it contain anything the user did not ask for?
- Is the requested element present, first, and in the requested format?
- Is the language the user's language?
- No trailing offer, no "let me know if", no appended explanation?