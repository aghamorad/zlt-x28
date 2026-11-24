# ZLT X28 — design

## Direction: the equipment control sheet

One scene decides everything: a warm room at night, the router on a shelf, someone
checking the connection before a call. The app should feel like the control sheet of a
piece of equipment — printed ink on a dark surface — not a SaaS dashboard.

The obvious template to refuse: neutral near-black app, blue accent, every block in a
14 px-rounded card with a soft border, a big title with tiny grey subtext, coloured pill
chips. That is what this app used to be.

## Material

- **Ground** `#171411` warm charcoal, not neutral black.
- **Panel** `#1F1B17`, raised `#27221D`. Surfaces are flat; depth comes from hairlines,
  never shadows.
- **Ink** `#EFE6D6` cream, muted `#A79A85`, faint `#6D6353`.
- **Signal** amber `#E39A4B` for the live thing and primary actions; green `#8FC3A4` for
  healthy; brick `#E0836F` for destructive. No second accent, no gradients.
- **Hairline** cream at 13 %; 22 % when it must read as a rule.

## Type

System sans, never rounded. Page title 27 semibold at −0.4 tracking. Section titles 13
semibold in ink. Body 13 in muted. Values 14 semibold with **tabular numerals** so IPs,
byte counts and timestamps never jitter. Captions 11.5.

No kickers or small tracked labels above headings. A heading carries itself; a hairline
separates the page header from the work.

## Geometry

Radii 6 for panels, 5 for sidebar rows, no pills except where something is genuinely a
token. One spacing rhythm: 20 between blocks, 18 inside a panel, 12 between label and
value. Siblings align on one left keyline.

Cards are allowed as **panels** because this is an instrument with distinct readouts, but
they never nest, never carry shadows, and explanatory copy is plain text — not a tinted
box inside a box.

## Voice

Plain words, complete sentences, no jargon undecoded. Say what happened and what to do
next. "The router stopped answering" is better than "timeout".

## Learned taste rules

- 2026-11-24 — Rename must be a prefilled, selected text field every time it opens; a
  text field that opens empty reads as broken.
- 2026-11-24 — Selection follows Finder: click, ⌘-click, ⇧-click, Select all, Delete key.
