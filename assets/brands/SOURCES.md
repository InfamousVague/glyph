# Brand marks

The marks the plugins wear for the companies whose products they reach (Matt, 2026-10-29: "Iconize real company logos
for openAI todoist, GitHub, Google meets, zoom etc and use those for the plugin icons"). Each `<slug>.svg` here is the
file as it was fetched, one path on a 24 by 24 view box; `brands.json` says the same of each as data;
`lib/art/brand_marks.g.dart` is made from both (`dart run tool/brands/generate.dart`), and
`test/art/brand_marks_test.dart` holds the three to one another.

**Trademarks.** Every mark here is a trademark of its owner. Ghost.md draws it only to say which service a plugin
reaches, inside the app; it implies no endorsement. No store listing or store screenshot shows one: a build made with
`--dart-define=GHOST_STORE_NEUTRAL=true` (the store pack's shoot scripts build so) draws every plugin's generic glyph
instead (`lib/art/brand_marks.dart`, `brandMarksShown`). The project's licence below covers the drawing as Simple Icons
publishes it, not the right to the mark, which stays with its owner and its brand guidelines.

## From Simple Icons

Simple Icons 16.35.0, from the npm package `simple-icons@16.35.0` (published 2026-10-11), fetched 2026-10-29 with
`npm pack simple-icons@16.35.0` into an empty directory and only its `icons/<slug>.svg` files read (and checked against
`https://cdn.jsdelivr.net/npm/simple-icons@16.35.0/icons/<slug>.svg`). The project's licence is CC0 1.0 Universal;
its colours are its data file's (`data/simple-icons.json`, `hex`).

| Plugin | Slug | Colour | Source | The owner's page Simple Icons names |
| --- | --- | --- | --- | --- |
| Claude | `claude` | `#D97757` | https://cdn.jsdelivr.net/npm/simple-icons@16.35.0/icons/claude.svg | https://claude.ai |
| Discord | `discord` | `#5865F2` | https://cdn.jsdelivr.net/npm/simple-icons@16.35.0/icons/discord.svg | https://discord.com/branding |
| ElevenLabs | `elevenlabs` | `#000000` | https://cdn.jsdelivr.net/npm/simple-icons@16.35.0/icons/elevenlabs.svg | https://elevenlabs.io/brand |
| GitHub | `github` | `#181717` | https://cdn.jsdelivr.net/npm/simple-icons@16.35.0/icons/github.svg | https://github.com/logos |
| Calendar (Google Calendar) | `googlecalendar` | `#4285F4` | https://cdn.jsdelivr.net/npm/simple-icons@16.35.0/icons/googlecalendar.svg | https://fonts.gstatic.com/s/i/productlogos/calendar_2020q4/v8/192px.svg |
| Gemini | `googlegemini` | `#8E75B2` | https://cdn.jsdelivr.net/npm/simple-icons@16.35.0/icons/googlegemini.svg | https://gemini.google.com |
| Google Meet | `googlemeet` | `#00897B` | https://cdn.jsdelivr.net/npm/simple-icons@16.35.0/icons/googlemeet.svg | https://about.google/brand-resource-center/logos-list/ |
| Notion | `notion` | `#000000` | https://cdn.jsdelivr.net/npm/simple-icons@16.35.0/icons/notion.svg | https://www.notion.so |
| Things | `things` | `#2473E7` | https://cdn.jsdelivr.net/npm/simple-icons@16.35.0/icons/things.svg | https://culturedcode.com/terms/#using_our_service |
| Todoist | `todoist` | `#E44332` | https://cdn.jsdelivr.net/npm/simple-icons@16.35.0/icons/todoist.svg | https://doist.com/press |
| Zoom | `zoom` | `#0B5CFF` | https://cdn.jsdelivr.net/npm/simple-icons@16.35.0/icons/zoom.svg | https://brand.zoom.us/usage-legal/ |

Claude's path is the one `lib/claude/claude_mark.dart` and the landing page already drew (the same string).

## From the company's own site

| Plugin | Slug | Colour | Source | Licence |
| --- | --- | --- | --- | --- |
| Lovart | `lovart` | none (drawn in the ink) | https://www.lovart.ai/, the inline `<svg>` beside the wordmark in the page's header, read 2026-10-26 (docs/LOVART.md; the same file as `assets/plugins/lovart/lovart-mark.svg`) | none given: Lovart's mark, used to identify the integration |

## Kept as glyphs

Companies' products whose marks the app has no copy of from either source, so their plugins keep the generic glyph
(`lib/plugins/brands.dart`, `pluginsWithoutMark`):

- **Slack** (`hash`): Simple Icons no longer carries Slack's mark, and Slack's media kit hands its logos out
  from Salesforce's Widen (salesforce.widencollective.com), not from slack.com.
- **OpenAI** (`brain`): Simple Icons carries no OpenAI mark, and openai.com/brand gave no file to fetch (it answered
  403 to a plain request, and asks for permission by mail for use of its logos).
- **Aster** (`asterisk`): Simple Icons has no Aster Lab, and asterlab.ai publishes no press kit and no SVG (its header
  logo is a PNG, `/aster_logo_dark.png`).
