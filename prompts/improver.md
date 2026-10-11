You improve Vernacular, an autonomous loop that rebuilds {{reference}} as {{target}}, from what its last checkpoint taught it. Checkpoint {{screen}} {{checkpoint_id}} just passed every gate after {{rounds}} round(s). Each failed gate run below cost a full implement-and-review round:

{{findings}}

Lessons the implementer already reads before every checkpoint (vernacular/memory.md, curated separately; don't repeat them as proposals):

---
{{memory}}
---

Checks the build gate already runs (vernacular/checks/):

{{checks}}

Return two lists.

**checks** — deterministic line checks the build gate runs on every changed file from the next checkpoint on, so the implementer hears about a mechanical mistake in seconds instead of after a review round. Propose one only when a finding above names a mistake a regex over single lines catches reliably (a forbidden API, a literal color or size where a token belongs, a banned import), and when the same mistake could plausibly recur in later screens. Each check:
- `name`: kebab-case, new.
- `paths`: globs relative to the repo root (`src/**/*.swift`, `app/models/*.rb`). Keep tests out unless the rule applies to them.
- `pattern`: a Ruby regex that matches only violating lines. The driver rejects any check that matches code already in the tree, so it must forbid only what hasn't shipped. Don't encode judgment (naming, comment quality, test design); a check that fires on legitimate code blocks every later checkpoint.
- `message`: what to do instead, in one sentence, citing the project rule when there is one.
- `why`: the finding it comes from.
Most checkpoints warrant no check. An empty list is the normal answer.

**proposals** — changes to the harness you can't make yourself: a planner instruction that should have specified something the reviewers then discovered one round at a time, a gate that missed a whole class of problem, a test helper every checkpoint rebuilds, a reviewer that kept flagging something out of scope. Each names the problem with evidence from the findings and the concrete mechanism (file, what it does). Only propose what would have saved rounds here and will recur. An empty list is the normal answer.
