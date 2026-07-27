# Test artifact schemas

Optional structures for keeping repeatable test cases alongside a skill. These are
agent-agnostic — use them when you want structured, rerunnable evals, not a
requirement. Read this file only when formalizing tests.

## evals.json

Lives at `evals/evals.json` within the skill directory. Captures the prompts you
test the skill against, plus what a good result looks like.

```json
{
  "skill_name": "example-skill",
  "evals": [
    {
      "id": 1,
      "prompt": "The realistic task a user would actually type",
      "expected_output": "Human-readable description of what success looks like",
      "files": ["evals/files/sample1.pdf"],
      "expectations": [
        "The output includes X",
        "The skill invoked script Y instead of re-deriving it"
      ]
    }
  ]
}
```

**Fields**
- `skill_name`: matches the skill's `name` frontmatter.
- `evals[].id`: unique integer.
- `evals[].prompt`: the task to run.
- `evals[].expected_output`: prose description of the desired result.
- `evals[].files`: optional input files (paths relative to the skill root).
- `evals[].expectations`: optional list of objectively checkable statements. Keep
  each one verifiable and specifically worded, so pass/fail is unambiguous. Skip
  these for subjective skills (writing style, design) where human judgement beats
  a checklist.

## A note on grading

For simple manual iteration you don't need a formal grading file — read the
outputs and transcripts, compare against `expected_output`/`expectations`, and
note what to improve. If you want to record results, a flat list of
`{ "text": ..., "passed": true|false, "evidence": ... }` per expectation is enough
to track progress across iterations.
