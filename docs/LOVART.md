# Lovart

Matt, 2026-10-26: "I'd like to build a Lovart.ai plugin into the app. They have a API for OpenClaw and I think we can
build a wrapper around that in order to create images automatically based on notes and with some custom inline syntax.
For example during design meetings the Lovart.ai plugin can generate inspo images and such. Please create the basics of
the plugin and do research on OpenClaw for Lovart."

The plugin is `lib/plugins/lovart/`. It is a built-in plugin, off until added in Settings › Plugins (category AI),
because it sends words to Lovart and spends the person's Lovart credits.

## OpenClaw, and how Lovart plugs into it

**OpenClaw** (github.com/openclaw/openclaw, MIT) is an open-source personal agent that runs on your own machine and is
extended by *skills*: a folder with a `SKILL.md` that tells the agent when and how to use it, and scripts it runs.
Skills are shared on **ClawHub** and installed with the `skills` CLI.

**Lovart** (lovart.ai) is a "design agent": you describe an image, a set of images, a video or a brand kit, and its
agent picks models and makes them on a canvas in a Lovart project. Lovart has no public, documented REST API. What it
publishes for agents is the **Lovart skill**:

- source: github.com/lovartai/lovart-skill (`skills/lovart-skill/SKILL.md`, `scripts/agent_skill.py`);
- install: `npx skills add lovartai/lovart-skill`, or from ClawHub as `@lovart-admin/lovart-skill`;
- it is a zero-dependency Python client over what the skill calls **"Lovart Agent OpenAPI"**, authenticated with an
  access key / secret key pair (AK/SK) the user makes in Lovart: avatar menu › **AK/SK Management**.

So "the API for OpenClaw" is that HTTP API. This plugin does not run OpenClaw or the Python skill: it calls the same
API directly from the app (`client.dart`), ported line for line from `agent_skill.py` **as read on 2026-10-26**. The
API is undocumented and can change without notice; when it does, that file is the reference to re-read.

## The API

Base `https://lgw.lovart.ai`; every path begins `/v1/openapi`.

| Call | Body / query | Answers (`data`) |
| --- | --- | --- |
| `POST /mode/query` | `{}` | the account's mode and models; changes nothing, so the plugin uses it to **check keys** |
| `POST /project/save` | `{"project_id":"","canvas":"","project_cover_list":[],"pic_count":0,"project_type":3}` | `project_id` of a new project |
| `GET /project/validate` | `?project_id=` | `valid`, `project_name` |
| `POST /chat` | `{"prompt","project_id","thread_id"?,"mode"?}` (the plugin sends `"mode":"fast"`) | `thread_id` |
| `GET /chat/status` | `?thread_id=` | `status`: `running`, `done` or `abort` |
| `GET /chat/result` | `?thread_id=` | `items[]`, `failures[]`, maybe `pending_confirmation` |
| `POST /chat/confirm` | `{"thread_id"}` | approves a costly step. **The plugin never calls it.** |

Other calls the skill has and the plugin does not use yet: `/mode/set` (fast vs unlimited queue), file upload,
model preferences (`tool_config.include_tools` / `prefer_tool_categories`; SKILL.md lists the tool names, e.g.
`generate_image_midjourney`, `generate_image_nano_banana_pro`), brand kits and subjects, project rename.

**Signing.** Each request carries `X-Access-Key`, `X-Timestamp` (unix seconds), `X-Signature` =
`hex(HMAC-SHA256(secretKey, "METHOD\npath\nseconds"))` with the path *without* its query, `X-Signed-Method`,
`X-Signed-Path`, `Content-Type: application/json`, and a browser-like `User-Agent`
(`Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) LovartAgentSkill/1.0`): Cloudflare in front of Lovart refuses
library defaults. A POST also sends `Idempotency-Key` (a uuid hex), the same on every retry. Each retry is signed again.
HMAC is `package:crypto`, already a dependency (pubspec.yaml); no new package.

**Envelope.** `{"code":0,"message":…,"data":{…}}`; `code` not 0 is an error whose `message` is a sentence for the
person. HTTP errors carry JSON `message` (and `details`). Known: **401** keys wrong; **402 / code 2012** credits, plan,
free tier, risk control, phone verification and the like (Lovart's message is shown as-is); **409 / code 2011** a task
already running on the thread; **429** rate limited (the plugin waits `Retry-After`, at most a minute, then tries once
more). GETs are retried on 404/502/503 and dropped connections, as the skill does.

**Polling.** Status every 3 s. On `done`, wait 5 s and look again (the agent's sub-tasks can start late), then fetch
the result. From the seventh poll, every third poll also reads the result for `pending_confirmation`, which never
finishes by itself. The plugin gives up after 5 minutes.

**Results.** Images are `items[type == "generator"].artifacts[type == "image"].content`, URLs on
`assets-persist.lovart.ai`, fetched with `Referer: https://www.lovart.ai/`. `done` with no artifact means the agent
declined (moderation) or answered in words: the plugin says the assistant's text (`LovartRefused`).
`pending_confirmation` (a premium model, a video) is said with its `estimated_cost` (`LovartNeedsConfirmation`) and the
cue stays; the person approves it in Lovart if they want it.

**No size, shape or count parameters.** Those go in the prompt's words ("Make one image.", "four separate images").

**Limits.** Reported as chat 60 a minute and 600 an hour, queries 300 a minute; those figures are not in the skill's
source as read here, which says only that a 429 (code 1429) means "retry in ~60s". Treat them as unconfirmed.

**Hosts.** The manifest lists `lovart.ai`, which covers `lgw.lovart.ai` and `assets-persist.lovart.ai`; the host
refuses anything else, and an artifact URL elsewhere is skipped.

## Keys, credits and terms

- Each person brings **their own** AK/SK. There is no shared Ghost.md key, and none should be added: the keys bill the
  person's Lovart credits, and Lovart's terms are written for a user's own use of their account.
- The keys are kept in the device's secure store (`glyph-lovart-access-key`, `glyph-lovart-secret-key`) and follow the
  account **sealed** with the other connections (lib/sync/connections.dart), with the plugin's switch. The project id
  and the meetings switch stay on each device.
- Every image costs Lovart credits. Which Lovart plans include AK/SK access is not documented; ask Lovart before relying
  on it for a team.

## What the plugin adds

**Inline syntax: `{image: a prompt}`.** Anywhere in a line; `{image:prompt}` and any case of `image` work. It is a cue
once the closing `}` is there and the prompt has words. Not after `{`, `$` or `\`, not closed by `}}`, not in code. It
never collides with the blanks, which begin `{?` (lib/core/blanks_syntax.dart). While the plugin is on, the editor washes
the cue faintly and draws Lovart's mark just after it (lib/editor/ai/lovart_cues.dart); a tap makes that cue, and the
mark turns while it is made. With the plugin off it is plain text.

A cue alone on its line becomes `![prompt](image/lovart-<uuid>.png)`; a cue among words is taken out of the words and
the picture goes on its own line after (after any pictures an earlier cue on that line put there).

**Make images** (note's cog, shown when the note has cues): every cue in order, saying progress. A refusal leaves that
cue and goes on; bad keys, credits or a step awaiting confirmation stop the rest.

**Inspiration images** (note's cog): a moodboard of four from the note's title and its summary (or its first 1500
characters), one image per artifact, appended under `## Inspiration` (or added to the one there is).

**Inspiration for design meetings** (switch on the plugin's page, off by default): when a meeting is written up
(lib/root/root_voice.dart `meetingSummarized`, after the sorter and Slack), a meeting whose title has a design word, or
whose summary has two different ones (design, mockup, wireframe, UI, UX, brand, logo, moodboard, visual, palette,
typography, layout, prototype, illustration, Figma, style guide, icon…), gets the same section in the closed note.
Once per meeting, remembered before Lovart is asked.

**Header images** (switch on the plugin's page, **on** by default; Matt, 2026-10-26: "add a setting to automatically
generate header images for notes (turn it on by default when lovart is enabled)"): a banner across the top of a note,
made when the note is **left** (lib/root/root_parts.dart `onScreenChanged` → lib/plugins/lovart/banners.dart
`LovartBanners.noteLeft`), and on the note's cog as **Header image** (makes one again where there is one). The prompt is
the house style, the ghost's stipple dotwork word for word from tauri/docs/GHOSTS.md (`bannerStyle`), with the note's
title and its first 900 characters as the subject; 4:1, the ghost small on the right two-thirds, the left third white.
The banner is front matter `banner: "![](image/lovart-….png)"` (lib/core/banner.dart): a picture's own Markdown, so
sync, team sync, export and the trash's sweep follow it with no change. The note page draws it under the header
(lib/note/note_banner.dart) in the page's inks, white as paper and black as ink, so it turns over in dark mode as the
ghost scenes do. Made by itself only for a note of 25 words or more that is not a ticket, a meeting (Ghost's, or a
recording with a summary), a mail (`from:`), a notebook, a canvas or a template, has no banner, and was never given
one: remembered by id before Lovart is asked, so a banner taken off is not made again.

**The badge.** A picture whose name begins `lovart-` carries Lovart's mark at its bottom right (20 px on a dark rounded
ground, inset 8 px, "Made with Lovart" to a screen reader) wherever it is drawn: the editor's figures, an embedded
note, a canvas picture card, on every device, plugin on or not (lib/editor/media/lovart_badge.dart).

## The mark

`assets/plugins/lovart/lovart-mark.svg` is the round "Lo" mark from the header of **https://www.lovart.ai/** (the
inline `<svg>` beside the wordmark, read 2026-10-26; the page's `<link rel=icon>` is `/favicon.ico`, and the logo its
JSON-LD names, `https://assets-persist.lovart.ai/web/logo/lovart-logo.svg`, answered 404). Its fill is set to black
and recoloured where it is drawn (`flutter_svg`, already a dependency; lib/plugins/lovart/lovart_mark.dart). It is a
third party's mark: it is drawn only in the plugin's own places (its page, its actions, the cue's mark, the badge), and
never in the store listing or its screenshots. The catalogue card uses the Lucide `palette` icon.

## Left for later

- A model picker (the skill's `tool_config.include_tools`, e.g. Midjourney, Nano Banana Pro, GPT Image) and fast vs
  unlimited mode (`/mode/set`).
- Approving a pending costly step from the app (a confirm button that names the cost), and resuming a thread that timed
  out (`/chat/result` again later).
- Attachments: sending a note's own pictures as references (`/upload`).
- A link to the Lovart canvas (`https://www.lovart.ai/canvas?projectId=…`) on each picture.
- A cue said aloud while recording ("Ghost, image of …").
