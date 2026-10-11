# Vernacular

Vernacular rebuilds an app in a new stack one screen at a time and leaves nobody at the keyboard. Claude Code plans each screen, then implements it in small checkpoints. A checkpoint is committed only after every machine gate passes.

It's an open-source take on Shopify's [Helix](https://shopify.engineering/helix), which proved the core idea: **an attempt may be wrong; it may not ship until it isn't.** Vernacular removes the engineer approval gate. Machines enforce every gate, and a checkpoint that can't pass them gets set aside rather than waved through.

## Example

[Prep Slate](https://prepslate.com)'s Hotwire Native iOS app (left) and the fully native SwiftUI app built from it (right) by the loop Vernacular was extracted from. Both show the same library on iOS 26.

![Library: Hotwire Native vs. SwiftUI](docs/library.jpg)
![Recipe page: Hotwire Native vs. SwiftUI](docs/recipe.jpg)

## Requirements

Ruby 3.4+, git, and the [`claude`](https://docs.claude.com/en/docs/claude-code) CLI, signed in.

## Install

```bash
git clone https://github.com/mark-kraemer/vernacular && cd vernacular
gem build vernacular.gemspec && gem install vernacular-*.gem
```

## Use

```bash
vernacular init              # scaffold vernacular/ in your repo
$EDITOR vernacular/config.yml vernacular/queue.yml
git commit -am "vernacular setup"
vernacular run               # plan and build every pending screen, unattended
vernacular status            # what's running, the queue, ledgers to read
vernacular pause             # stop cleanly after the current checkpoint
```

Run a single screen with `vernacular run <screen>`. Run only its planning step with `vernacular plan <screen>`. `vernacular capture` and `vernacular shoot` produce the reference and target screenshots by hand.

## The loop

```
plan ──► for each checkpoint:
           implement ─► build ─► behavior ─► UI ─► adversarial ─► (UI again if pixels changed) ─► regression ─► commit
               ▲           │         │        │          │                                          │
               └───────────┴─────────┴────────┴──────────┴─────────── findings ──────────────────────┘
```

- **plan.** A planner writes `vernacular/screens/<screen>/plan.yml`. Each checkpoint lists a goal, the screen states to compare, and the test names that must pass. The driver checks the plan's shape and proves every state renders in the reference app before any code is written.
- **build / behavior / regression.** These gates run your commands and read exit codes. Every planned test must appear as passed in the output.
- **UI.** Your capture commands screenshot each state in both apps, and a fresh reviewer compares each pair.
- **adversarial.** Fresh, read-only reviewers check the diff against your docs and return structured findings. Every finding must be fixed.
- **Memory and checks.** After each commit, a curator folds the round's findings into `memory.md`. An improver turns findings a regex can catch into `checks/*.yml`, which the build gate runs from then on.

Each fix round resumes the implementer's session. Reviewers never share context with it or with each other. Gates read exit codes and schema-constrained JSON, so the model never decides whether a gate passed.

## Config

`vernacular/config.yml`. [templates/config.yml](templates/config.yml) documents every key, and [examples/rails-to-swiftui](examples/rails-to-swiftui) is a full setup.

| Key | What it does |
|---|---|
| `reference`, `target` | One line each, used in every prompt |
| `read_first`, `hard_limits`, `planning` | What the agents read and must not do |
| `scenarios` | Where the planner writes a screen's scenarios |
| `commands.lint/build/test/regression` | The gates |
| `commands.test_passed` | Regex proving a named test passed (`{name}` is substituted) |
| `commands.capture_reference/capture_target` | Write `$VERNACULAR_OUTPUT/<scenario>/<state>.png` |
| `reviewers` | Name → docs to enforce + focus. Edits to those docs are logged to `decisions.md` |
| `visible` | Paths whose change re-runs the UI gate |
| `tools` | Extra Claude Code permissions for the implementer |

To override a prompt, put a file of the same name in `vernacular/prompts/` (for example `architecture_reviewer.md`). [prompts/](prompts) has the defaults.

## Guardrails

- The implementer works from a tool allowlist. It can't commit, push, reset, stash, delete files, browse the web, or spawn agents. Reviewers are read-only.
- After `max_rounds`, the checkpoint's work is stashed (`vernacular blocked <screen>/<checkpoint>`), the screen is marked blocked, and the run moves on to the next screen.
- The improver can only add checks, and each new check must match nothing already in the tree. Checks are read from HEAD, so the implementer can't loosen one.
- Only one run at a time. Vernacular never pushes or opens PRs; a human reviews the branch.

## Files

`vernacular/` is committed: config, queue, memory, plans, checks, `evidence/<screen>/<checkpoint>/` (every gate verdict and review), `decisions.md`, and `improvements.md`. `tmp/vernacular/` holds screenshots, logs, and per-round findings.

## License

MIT
