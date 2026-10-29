# AI providers: Claude, OpenAI, Gemini and any OpenAI-compatible model

Matt, 2026-10-29: "Add support for aster 6 and other Ai models as plugins in addition to claude like openAI google gemini etc".

The app's own AI assistant (the dock's chat, Ask, talking to it, the "Ask Claude" note's runner, meeting summaries) was Claude's alone (docs/CLAUDE_APP.md). It is now one seam with a provider behind it, Claude one of four. Claude's path is the one it always was; every existing Claude test passes untouched.

## The seam

`lib/assistant/` holds what every provider shares; each provider's own code is in its plugin's folder.

- **One shape of conversation: the Messages API's.** Claude's run (`lib/claude/claude_run.dart`) was written round it: blocks of text, thinking and tool calls, tool results, and a stream of `message_start`, `content_block_start/delta/stop`, `message_delta` (stop reason, usage), `message_stop`, `error`. Rather than a second run, every other client takes a request in that shape and answers in those events, translating both ways as it reads. So the tools, the live typing into a note, follow-ups, the spending limit and the meetings' write-ups are the same code for every provider.
- **`AiStreamer` / `AiProvider`** (`lib/assistant/provider.dart`): `stream(body)` for a chat turn with tools; `aiText(call)` reads one completion whole (summaries); `models()` lists what the key may ask; `check()` says whether the key works (the models list, which nobody bills); usage arrives in the events and is priced by the plugin's rates; errors are `AiError`, in a sentence, with the Messages API's error types (`authentication_error`, `billing_error`, `rate_limit_error`, `permission_error`, `not_found_error`, `overloaded_error`).
- **Claude is one implementation.** `ClaudeApi` implements `AiProvider` (it gained `models()`); `ClaudeError`, `ClaudeCancelled` and `ClaudeCall` are type aliases of `AiError`, `AiCancelled` and `AiCall`; `lib/claude/sse.dart` hands on `lib/assistant/sse.dart`.
- **The network** is `dart:io`'s `HttpClient`, as the Claude client's (`lib/assistant/http_stream.dart`: `aiPostStream`, `aiGetJson`). No SDK, no new dependency.
- **A model without tools**: a 400 that says the model takes no tools is asked again at once without them, and the chat says so once (a `ghost_notice` event, shown as a notice step); that model is asked without them for the rest of the app's run. Each provider page also has a Tools switch.

## The providers

| Plugin (id) | Client | Streaming | Key check / models | Default model |
|---|---|---|---|---|
| Claude (`claude`) | `lib/claude/messages_api.dart` | `POST api.anthropic.com/v1/messages` | `GET /v1/models` | its three, as before |
| OpenAI (`openai`) | `lib/plugins/openai/chat_api.dart` | `POST api.openai.com/v1/chat/completions`, `stream: true`, `stream_options.include_usage`, `max_completion_tokens`, function tools | `GET /v1/models`, cut to chat models | the newest plain `gpt-N` in the list (`openAiFlagship`) |
| Gemini (`gemini`) | `lib/plugins/gemini/gemini_api.dart` | `POST generativelanguage.googleapis.com/v1beta/models/{model}:streamGenerateContent?alt=sse`, key in `x-goog-api-key`, `functionDeclarations` | `GET /v1beta/models` (pages), cut to `generateContent` Gemini models | the newest stable Pro, else Flash (`geminiDefault`) |
| Custom AI model (`custom-ai`) | OpenAI's client at the given address | `POST {base}/chat/completions`, `max_tokens` | `GET {base}/models`; none is fine, the model is typed | the first listed, or typed |

**Model ids are read, not written.** Each plugin keeps a small fallback list, said on its page to be possibly out of date (OpenAI: `gpt-5`, `gpt-5-mini`, `gpt-4.1`; Gemini: `gemini-2.5-pro`, `gemini-2.5-flash`). When a list is read and no model is chosen yet, the first listed is kept as the choice, so the default holds after a restart until the person chooses another.

**Translation, OpenAI-compatible.** System prompt → a `system` message; a user turn's `tool_result` blocks → `tool` messages (in order, before the turn's words); `tool_use` blocks → `tool_calls` with JSON arguments; thinking blocks, `thinking` and `output_config` dropped. Back: `delta.content` → text; `delta.reasoning_content`/`reasoning` → a thinking block; each `tool_calls[i]` → a `tool_use` block opened once its name is known and fed its arguments however they were cut; `finish_reason` `tool_calls` → `tool_use`, `length` → `max_tokens`, `content_filter` → `refusal`, and `stop` after tool calls → `tool_use` (some local servers); usage from the last chunk (cached tokens as cache reads). A server that knows no `stream_options` is asked again without.

**Translation, Gemini.** `systemInstruction`, `contents` of `user`/`model` with `text`, `functionCall` and `functionResponse` parts (named by the call they answer), schemas cut to Gemini's subset. A thinking model's `thoughtSignature` on a function call must go back with it: it rides in the tool call's id (`gemini_<n>~<signature>`). `MAX_TOKENS` → `max_tokens`; `SAFETY`, `RECITATION`, `BLOCKLIST`, `PROHIBITED_CONTENT`, `SPII` and a blocked prompt → `refusal`.

**Errors.** OpenAI: 401 refused key; 429 with `insufficient_quota` (or 402) no credit, else too many requests; 403 not allowed; 404 no such model or address; 5xx the provider's trouble; no answer the connection. Gemini: a wrong key is Google's 400 `API_KEY_INVALID`, read as refused; 403 `PERMISSION_DENIED`; 429 `RESOURCE_EXHAUSTED` (the free tier's daily quota, or too many requests); 404; 5xx.

## The key, the settings, the sync

`lib/assistant/provider_settings.dart`, one class for the three, each under its prefix (`openai`, `gemini`, `custom-ai`) in the device's secure store: `-api-key`, `-model`, `-base-url` (custom), `-meetings`, `-tools`, `-rates`, `-spend`, `-limit`. All but `-spend` (this month's count, each device's own) follow the account sealed, as Claude's do (`lib/sync/connections.dart`), with the three plugins' switches and the assistant's two choices.

## Spending limit

Each provider has Claude's limit (`ClaudeSpend`, under its own names, its own words "Settings › OpenAI"). No provider's API says its prices, so the meter counts at the page's **Prices** (US dollars a million tokens, input and output): $10 / $40 until the person sets their model's, a high guess so the limit is reached early rather than late. OpenRouter's listing gives prices per model, and those are used where the person set none.

## The assistant

`lib/assistant/assistant.dart`, the app's instance `lib/assistant/app_assistant.dart`. Settings › AI › Assistant has two choices:

- **Chat and Ask**: Automatic (default), Claude, OpenAI, Gemini or Custom AI model. Automatic is Claude where its plugin is on and a key kept, else the first other provider set up (Market order), else nobody (the dock has no chat, as with no key today). A provider chosen by name answers while it can; when it can't, Automatic stands in.
- **Meeting summaries**: the same, plus On this device. Each provider's own "Write meeting summaries with (name)" switch says whether it may; Automatic is Claude where it may (exactly as before), else the first other provider that may, else the device's model. Local only holds a chosen provider (the job waits), as it holds Claude.

The runner (`lib/claude/claude_runner.dart`, `route:`) and the meetings' write-up (`lib/ai/summary_claude.dart`, `choice:`) read it; with none given they are Claude's as before. A conversation is one provider's: an ask after the answer moved starts afresh. Another provider is asked with the same tools and a system prompt that calls it "an AI assistant"; Claude's still says "You are Claude". The chat, the bar and the dock name whoever answers; Claude's model and effort picker show only for Claude. Another model's room is not known, so a meeting goes to it in pieces past 120,000 characters (Claude's one pass is 800,000).

## Its page and its setup

`lib/assistant/provider_pane.dart` and `provider_setup.dart`, in each plugin's words (`AiProviderPage`). The page: the key (or the endpoint's address and an optional key), checked before it is kept; the model from the provider's list; Tools; Meeting summaries; Spending limit with Prices; and plainly what goes where. The setup: intro → account → key → paste → check → settings (the custom endpoint: intro → address and key → check → settings), the check reading the models for the last step. The words are captions only (`setupCaptions` in `lib/plugins/onboarding/setup_voice.dart`), with no voice clip. Setup links (platform.openai.com, aistudio.google.com) are marked unverified: they weren't opened while this was written.

## Privacy

Each plugin's permission, page, setup and Market card say it: what you ask, the notes it reads to answer, and with meeting summaries on a meeting's transcript, go from the device to the provider (or the address you give) under your own key, and nowhere else: not through Ghost.md's server.

## What is still Claude's alone

- The connector (Ghost.md's MCP server, "From Claude's own app").
- The "Ask Claude" note's switch (`claudeInApp`): its requests are run by whoever answers, but the inbox only runs while the Claude plugin is on.
- The model and effort picker in the chat, adaptive thinking and its summaries, the server-side fallback, the one-pass meeting size.
- The watch's To Claude switch and the phone-assistant card live on Claude's page.
- The "Claude rules" note is read as the standing instructions for every provider.

## Aster 6

TODO: Matt named "Aster 6"; its provider isn't known yet. Until it is, it is reached through Custom AI model if it offers an OpenAI-compatible endpoint. No Aster-branded plugin was added.

## Store

In-app naming of providers is fine. No store metadata or screenshots changed (docs/store/ untouched). The website's Market listing (`landing/market.json`) was made again, as its drift test asks; it shows each plugin's Lucide icon, no brand marks.

## Tests

Fake HTTP only (`test/assistant/fake_http.dart`): `test/assistant/assistant_test.dart` (the seam, the choice, the runner's and the write-ups' routing), `test/plugins/openai/chat_api_test.dart`, `test/plugins/gemini/gemini_api_test.dart`, `test/plugins/ai_providers/setup_test.dart` (setups, pages, privacy words), `test/settings/ai_assistant_test.dart`, the sealed sync in `test/sync/sealed_keys_test.dart`. Pictures: `flutter test --no-pub --update-goldens test/plugins/ai_providers/shots_test.dart` → `build/feature-shots/ai-providers/`.
