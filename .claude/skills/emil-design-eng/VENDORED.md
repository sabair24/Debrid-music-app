# Where these came from

Not written here. Copied from **[emilkowalski/skills](https://github.com/emilkowalski/skills)**,
commit `78761e1` (2026-08-10). MIT, licence alongside this file.

Ten skills, all plain Markdown — no scripts, no data, nothing that reaches the network:

| Directory | What it is |
|---|---|
| `emil-design-eng` | The philosophy underneath the rest: UI polish, component design, the invisible details |
| `apple-design` | Springs, gestures, sheets, momentum, interruptible transitions, reduced motion |
| `animate` | Building one animation, in the order the decisions actually matter |
| `review-animations` | Critiquing motion in a diff, against a high bar |
| `improve-animations` | Auditing a whole codebase's motion and planning fixes |
| `find-animation-opportunities` | Where motion is missing — and where it would be wrong |
| `animation-vocabulary` | Reverse glossary: "the bouncy thing when a popover opens" → Pop in |
| `prototype` | Several genuinely different versions behind a picker |
| `pick-ui-library` | Curated frontend library picks |
| `ask-sonner` | The Sonner toast library |

## What was changed

Nothing. Every directory name already matched its frontmatter `name:`, so the files are byte-for-byte
upstream. Only the repository's own README and licence were left behind — the licence is here.

## What applies to this app, and what does not

These are written against React and CSS, but unlike a landing-page skill the **subject** transfers:
duration and curve, what interrupts what, exits faster than entrances, spatial continuity, motion
that means something rather than decorates. All of that is as true of an `AnimatedContainer` and a
`CurvedAnimation` as of a CSS transition. Read the reasoning, write the Dart.

`apple-design` is the closest fit for this app — sheets, drag, momentum, translucent depth and
reduced motion are exactly the phone surfaces being built. `animate`, `review-animations` and
`find-animation-opportunities` are worth reaching for around `AlbumArt`'s sliding disc, the
now-playing transition and the section bar.

Two do not apply and are here only because the set was installed whole: `ask-sonner` is a React
toast library, and `pick-ui-library` picks npm packages. Neither can be used from Dart.
`pick-ui-library`, `prototype` and `review-animations` carry `disable-model-invocation: true`, so
they stay quiet until asked for by name.

As always: this repository's conventions win. Dutch interface strings, a comment naming the pixel
failure it fixes, and — for motion specifically — the app already has opinions worth respecting,
like the disc that slides out from behind the sleeve and the reserved width that pays for it.
