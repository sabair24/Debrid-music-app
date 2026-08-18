# Where this came from

Not written here. Copied from **[nextlevelbuilder/ui-ux-pro-max-skill](https://github.com/nextlevelbuilder/ui-ux-pro-max-skill)**,
commit `a38d04c` (2026-08-14), plugin version 2.13.0. MIT, licence alongside this file.

Vendored into the repository rather than installed as a plugin so it travels with the project: any
session that opens this repo has it, on any machine, without a separate install step.

## What was changed

Two things, both about the move from plugin to repository:

1. Every `${CLAUDE_PLUGIN_ROOT}/.claude/skills/…` path in `SKILL.md` became
   `.claude/skills/ui-ux-pro-max/scripts/search.py`. That variable is set for installed plugins and
   for nothing else, so left alone every command in the file would have resolved to `/…` and failed.
2. The sentence telling you to invoke the script by its full path now says to run it from the
   repository root, which is what the rewritten paths assume.

Nothing under `scripts/`, `data/` or `references/` was touched.

## What was left behind

The upstream repository ships seven skills. Only `ui-ux-pro-max` is here — it is the one with the
searchable database and the Flutter stack. The other six (`banner-design`, `brand`, `design`,
`design-system`, `slides`, `ui-styling`) are for brand systems, slide decks and banner artwork, and
`ui-styling` alone carries 5.8 MB of TrueType fonts for rendering images. None of it applies to a
music player, so none of it is here. Copy any of them in the same way if that changes.

## Updating

Clone upstream, copy `.claude/skills/ui-ux-pro-max` over this directory, and redo the two changes
above. The search script is pure standard-library Python 3 and reaches no network, so there is
nothing else to check.

## Using it

```bash
python3 .claude/skills/ui-ux-pro-max/scripts/search.py "bottom navigation back behavior" --domain ux
python3 .claude/skills/ui-ux-pro-max/scripts/search.py "list scroll performance" --stack flutter
```

Its own guidance says it plainly, and it holds here: the results are recommendations. This
repository's own conventions win — the Dutch interface strings, the comment that names the pixel
failure it fixes, `isCompact` as a width rather than a device class.
