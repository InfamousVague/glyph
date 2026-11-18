# Vendored Glacier (Flutter)

A copy of `packages/glacier` from InfamousVague/glyph (Ghost.md), taken from Ghost Keyboard's vendored copy (itself
Ghost.md at commit c10a10b, 2026-11-05), tests left out. Edit the kit upstream in Ghost.md and copy it back here,
rather than diverging.

Local addition (2026-11-18), optional and off unless an app sets it: `GlacierOverrides.segmentedSegment` with
`GlacierSegmentLook`, which lets an app draw each segment of a `GlacierSegmentedControl` itself in place of the track
and sliding thumb (Ghost Messaging's Dial-Up look draws them as push buttons). Copy it upstream with the next sync.
