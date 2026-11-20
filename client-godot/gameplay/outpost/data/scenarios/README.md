# Isles of Mythos — Scenario Library

Randomised, research-grounded event scenarios for the outpost event engine.

## Counts
| Category | Scenarios |
|---|---|
| castaway | 32 |
| discovery | 11 |
| faction | 11 |
| gathering | 30 |
| mystery | 22 |
| pet | 22 |
| pirate | 33 |
| sea | 22 |
| weather | 21 |
| wildlife | 25 |
| **Total** | **229** |

Chained mini-stories: 30 chain starts, 141 next_event links, 49 follow-up scenarios.
Rejected during QA: {'note_fixed': 24, 'few_outcomes': 23, 'no_intro': 3}.

## Files
- `<category>.json` - one JSON array per category (castaway, gathering, weather, sea, pirate, faction, discovery, mythos, pet, mystery).
  **Exception:** wildlife *scenarios* are in `wildlife_events.json`, because `wildlife.json` is the bestiary.
- `wildlife.json` - bestiary: behaviour, aggro rules, HP, damage, drops, tameable, pet synergy, source.
- `pet_training.json` - Tide-Puck: 10 levels, XP sources, commands, mood and trust.
- `items.json` - all item ids used, with name and description.
- `research_notes.md` - sources (castaways, survival science, Golden Age piracy, island wildlife).
- `stats.json` - machine-readable counts.

## Schema conventions
- Exact schema from the brief; validated by `validate.py`: ids unique, 1-3 intro lines of at most 60 chars, 2-4 choices, 2-3 outcomes per choice, outcome chances sum to 1.0, item and spawn ids from the allowed lists, every next_event resolves.
- **Chain follow-ups** have `trigger.chance = 0`, so they fire only via an outcome's `effects.next_event`.
- `requires` is `{}` or `{item_id: qty}` or `{"pet_level": n}`.
- `unlock` strings are free-form flags (e.g. `brackish_well`) for the engine to record.
- Negative `items` values are losses.

## Generation
Drafted in batches by the free Kilo CLI (`kilo run`, model `kilo-auto/free`) from `research_notes.md`. The Gemini CLI was over its free quota (HTTP 429 and 503). Then machine-validated, normalised, deduplicated and tone-filtered. Bestiary, pet training and items were written by hand from the research.
