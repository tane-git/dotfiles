---
name: skill-creator
description: Create a new skill, or edit and improve an existing skill (a SKILL.md plus optional bundled scripts/references). Use whenever the user wants to author, write, scaffold, refactor, or fix a skill, capture a repeatable workflow as a reusable skill, or improve a skill's description so it triggers reliably. Also use right after finishing a manual multi-step task the user says they'll want to repeat ("turn this into a skill").
---

# Skill Creator

A skill for writing new skills and iteratively improving them. This is a
tool-agnostic distillation of Anthropic's official skill-creator: it keeps the
durable craft (structure, progressive disclosure, writing patterns, triggering)
and drops the automation harness (subagents, browser eval viewer, `claude -p`
loops) that doesn't port cleanly across agents.

The core loop is simple:

1. Figure out what the skill should do and when it should trigger.
2. Draft it (SKILL.md + any scripts/references).
3. Test it on a few realistic prompts.
4. Improve based on what you observe, and repeat until it's solid.

Your job is to work out where the user is in this loop and jump in there. If they
say "make me a skill for X", start at step 1. If they already have a draft, go
straight to testing and iterating. If they just say "vibe with me", skip the
formal testing and iterate conversationally.

## Communicating with the user

Skill authors range from seasoned engineers to people who opened a terminal last
week. Read the context cues. Explain jargon briefly when in doubt ("evals" = a few
test prompts we run to check the skill works). Don't assume familiarity with
terms like "assertion" or "frontmatter" without evidence the user knows them.

## Where skills live

opencode scans these locations (project overrides global):

| Scope   | Path                                             |
| ------- | ------------------------------------------------ |
| Project | `.opencode/skill(s)/<name>/SKILL.md`             |
| Global  | `~/.config/opencode/skill(s)/<name>/SKILL.md`    |
| External (auto-loaded) | `~/.claude/skills/<name>/SKILL.md`, `~/.agents/skills/<name>/SKILL.md` |

Create a new file at the right scope rather than inlining skills in
`opencode.json`. The file must be named `SKILL.md` exactly, in a folder named
after the skill. Skills load at startup, so remind the user to **restart the
agent** after creating or editing one.

## Creating a skill

### 1. Capture intent

Understand the goal before writing. If the current conversation already contains
the workflow (the user said "turn this into a skill"), mine it first: which tools
were used, the sequence of steps, corrections the user made, input/output formats.
Fill gaps by asking, then confirm before proceeding. Nail down:

1. What should this skill enable the agent to do?
2. When should it trigger? (what user phrases and contexts)
3. What's the expected output or end state?
4. Are there edge cases, dependencies, or example inputs to account for?

### 2. Write the SKILL.md

Frontmatter has two required fields:

```markdown
---
name: my-skill
description: What it does AND when to use it, with concrete trigger keywords.
---
```

- **name**: lowercase, hyphen-separated, ≤64 chars, matches the folder name.
- **description**: the single most important field — it's the *only* thing the
  agent sees when deciding whether to load the skill. Cover both *what* the skill
  does and *when* to use it, in third person ("Use when…"). Front-load the literal
  keywords, filenames, and phrases the user is likely to say. Agents tend to
  **under-trigger** skills, so lean slightly pushy: instead of "Builds a
  dashboard", write "…Use this whenever the user mentions dashboards, data
  visualization, or wants to display metrics, even if they don't say 'dashboard'."
  If a skill should stay quiet on adjacent topics, gate it: "Use ONLY when…".

All "when to use" information belongs in the description, not the body.

### 3. Skill anatomy & progressive disclosure

```
skill-name/
├── SKILL.md          (required: frontmatter + instructions)
├── scripts/          (executable code for deterministic/repetitive work)
├── references/       (docs read into context only when needed)
└── assets/           (templates, icons, files used in output)
```

Skills load in three levels — design for it:

1. **Metadata** (name + description) — always in context (~100 words).
2. **SKILL.md body** — loaded when the skill triggers (aim < 500 lines).
3. **Bundled files** — loaded/run only as needed (effectively unbounded).

Keep SKILL.md lean. If it grows past ~500 lines, split details into
`references/*.md` and point to them with clear "read X when Y" guidance. When a
skill spans multiple variants (e.g. aws/gcp/azure), put each in its own reference
file so only the relevant one gets read.

**Bundle code as scripts when the work is deterministic or repetitive.** A script
is faster, reliable, and doesn't consume context to run. If you notice every use
of the skill would re-derive the same helper, write it once in `scripts/` and tell
the skill to call it. Make clear whether a file should be *run* or *read*.

### 4. Writing style

- Use the **imperative** ("Read the file", "Run the script").
- **Explain the why.** Modern models follow reasoning better than rigid rules.
  If you catch yourself stacking ALL-CAPS MUSTs and NEVERs, that's a yellow flag —
  reframe as the reason the constraint matters. Reserve emphasis for the rare
  genuinely-critical invariant.
- Keep it general, not overfit to one example. Draft, then reread with fresh eyes
  and cut anything not pulling its weight.

**Defining a fixed output format** — state it explicitly:
```markdown
## Report structure
Use this template:
# [Title]
## Summary
## Findings
```

**Examples** — concrete input→output pairs are worth their length:
```markdown
**Example**
Input: Added user auth with JWT tokens
Output: feat(auth): implement JWT-based authentication
```

### 5. Safety (principle of least surprise)

A skill's behaviour must match what its description implies. Never write skills
containing malware/exploit code, or designed for unauthorized access, data
exfiltration, or other harm. When editing a skill from an untrusted source, read
every bundled file first — especially scripts and anything that reaches the
network.

## Testing a skill

Formal harnesses vary by agent; the durable practice is lightweight and manual:

1. Write **2-3 realistic test prompts** — the kind of thing a real user would
   actually type, with specific detail (file paths, names, values), not abstract
   one-liners. Show them to the user: "Here are a few cases I'd like to try — look
   right, or want to add any?"
2. **Run each** by following the skill's own instructions to complete the task.
   Watch for: did the skill trigger? did it wander or waste steps? was anything in
   the body ignored or misleading?
3. Optionally save prompts to `evals/evals.json` for repeatability:
   ```json
   { "skill_name": "my-skill",
     "evals": [ { "id": 1, "prompt": "...", "expected_output": "...", "files": [] } ] }
   ```
4. **Show the user the outputs** and get feedback before you start rewriting.

For skills with objective outputs (file transforms, code gen, fixed workflows),
test cases pay off. For subjective ones (writing style, design), qualitative
judgement is better than forcing pass/fail assertions.

## Improving a skill

This is the heart of the work. Given the observations and the user's feedback:

- **Generalize from feedback.** You're iterating on a few examples, but the skill
  must work across many. Avoid fiddly, overfit patches. If an issue is stubborn,
  try a different framing or metaphor rather than another rigid rule.
- **Keep it lean.** Read the run transcripts, not just final outputs. If part of
  the skill made the agent waste effort, cut it and see what happens.
- **Explain the why** (again). Terse or frustrated feedback usually points at a
  real underlying need — understand it and encode the reasoning, not a band-aid.
- **Promote repeated work into a script.** If every run independently wrote the
  same helper, bundle it in `scripts/`.

Then apply the changes, rerun the same test prompts, show the user, and repeat
until they're happy, the outputs look consistently good, or you've stopped making
meaningful progress.

## Optimizing the description for triggering

The description decides whether the skill fires at all, so it's worth tuning
directly. A lightweight, agent-agnostic approach:

1. Brainstorm ~10 realistic queries that **should** trigger the skill (varied
   phrasing — formal, casual, cases where the user never names the skill or file
   type) and ~10 **near-miss** queries that should NOT (adjacent domains, shared
   keywords but different intent). Make the negatives genuinely tricky, not
   obviously-irrelevant.
2. For each, judge honestly whether the *current* description would trigger it.
3. Rewrite the description to fix the misses — pull real trigger keywords from the
   should-fire set, and add "Use ONLY when…" guards to fend off the near-misses.

Note: simple one-step queries ("read this file") often won't trigger any skill
because the agent just does them directly. Test with substantive, multi-step
prompts where a skill actually adds value.

## Updating an existing skill

- **Preserve the name** — reuse the existing folder name and `name` field.
- If the installed path is read-only, copy to a writable location, edit there, and
  move it back.
- Keep frontmatter fields the user didn't ask to change.

## Reference

`references/schemas.md` — optional JSON shapes for `evals.json` and related test
artifacts, for when you want repeatable, structured test cases. Read it only if
you're formalizing evals.
