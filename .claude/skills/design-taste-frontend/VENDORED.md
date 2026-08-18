# Where these came from

Not written here. Copied from **[Leonxlnx/taste-skill](https://github.com/Leonxlnx/taste-skill)**,
commit `dfb6f9f` (2026-08-18). MIT, licence alongside this file.

Thirteen skills, all plain Markdown — no scripts, no data, nothing that reaches the network:

| Directory | Upstream folder |
|---|---|
| `design-taste-frontend` | `skills/taste-skill` |
| `design-taste-frontend-v1` | `skills/taste-skill-v1` |
| `gpt-taste` | `skills/gpt-tasteskill` |
| `high-end-visual-design` | `skills/soft-skill` |
| `minimalist-ui` | `skills/minimalist-skill` |
| `industrial-brutalist-ui` | `skills/brutalist-skill` |
| `redesign-existing-projects` | `skills/redesign-skill` |
| `full-output-enforcement` | `skills/output-skill` |
| `image-to-code` | `skills/image-to-code-skill` |
| `imagegen-frontend-web` | `skills/imagegen-frontend-web` |
| `imagegen-frontend-mobile` | `skills/imagegen-frontend-mobile` |
| `brandkit` | `skills/brandkit` |
| `stitch-design-taste` | `skills/stitch-skill` |

## What was changed

Only the directory names. Each one now carries the skill's own `name:` from its frontmatter rather
than the folder upstream happened to use — `brutalist-skill` announces itself as
`industrial-brutalist-ui`, and a directory that disagrees with the frontmatter is how a skill ends
up silently not loading. Not a byte of any `SKILL.md` was touched.

The repository's assets, examples, README and research notes were left behind; only `skills/` is
here.

## Read this before reaching for one

**This collection is written for the web.** Its vocabulary is CSS, Tailwind, GSAP, shadcn, bento
grids, npm packages and landing-page section structure. None of that exists in a Flutter widget
tree, and `design-taste-frontend` says so about itself in its first line: *"Landing pages,
portfolios, and redesigns. Not dashboards, not data tables, not multi-step product UI."* This app is
the second list.

What does carry across is the taste underneath the syntax — type scale, spacing rhythm, restraint
with shadows, what makes an interface look templated. Read those parts as principles and translate
them; do not follow a CSS instruction literally into Dart.

For anything stack-specific here, `ui-ux-pro-max` is the one to ask: it has a real Flutter dataset
(`--stack flutter`) and a searchable UX ruleset.

And as always: this repository's own conventions win. Dutch interface strings, a comment naming the
pixel failure it fixes, `isCompact` as a width and never a device class.
