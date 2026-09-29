# Task briefs for Codex

Each brief is self-contained and sized for one agent session. It says what
to build, where, the constraints, and how to prove it works. Read
`AGENTS.md` at the repository root first.

| Brief | Area | Size |
| --- | --- | --- |
| [01-wet-deck.md](01-wet-deck.md) | Rendering: decks darken and shine in rain and spray | Small |
| [02-bow-spray.md](02-bow-spray.md) | Rendering/physics: spray sheets when the bow slams, green water over the rail | Medium |
| [03-sail-damage.md](03-sail-damage.md) | Gameplay: overpressed canvas splits; hands aloft to bend new sail | Medium |
| [04-settings-menu.md](04-settings-menu.md) | UI: Esc settings menu (audio, mouse, quality) that persists | Small |
| [05-time-of-day.md](05-time-of-day.md) | Rendering: time-of-day slider, sun, dusk, night sky with stars and moon | Large |

## How to run one with the Codex CLI

From the repository root, on a branch of your own:

```
git checkout -b codex/wet-deck
codex "Read AGENTS.md, then implement docs/codex/01-wet-deck.md. Run the tests it lists and commit."
```

Or in Codex cloud, point a task at this repository and paste the same
instruction. Merge the branch back through a pull request once the brief's
checks pass.
