# Tests, and the report that ships

_The three suites, the tests that need a real server or real speech, and the report every release carries inside it._

## Three suites

| Suite | How it runs | What it holds |
|---|---|---|
| Page (Vitest) | `npm test`, which is `vitest run` | Every `*.test.ts(x)` under `src/`, `*.test.ts` under `mcp/` and `*.test.mjs` under `scripts/` |
| App (Rust) | `cargo test --lib` in `src-tauri/` | The shell's Rust. Tests that load a real model or reach the network are `#[ignore]`, and run only when asked |
| glyph-api (Rust) | `cargo test` in `server/` | The server |

`vitest.config.ts` runs the page's tests in jsdom. A file that needs a real socket asks for Node's environment on its first line (`// @vitest-environment node`). Globals are off, so every test file imports `describe`, `it` and `expect` from `vitest`. The build's stamps get fixed stand-ins, such as build `20260101000000` and version `0.0.0-test`.

`testTimeout` is 20 seconds, and the config says why. The first test in a file that mounts an editor is a cold CodeMirror render: about four seconds on an idle machine, and past Vitest's default five with a build running beside it, which once stopped a deploy with everything else green. Under twelve CPU hogs the same three tests took 8.2, 10.0 and 10.1 seconds, so fifteen would have held by a third and no more. A slow render still passes at twenty; a test that has really hung still fails.

## The shared fixtures

`src/test/` holds what many test files need, each written once:

- `setup.ts` loads the DOM matchers and gives `Range` empty rectangles. CodeMirror measures text by asking ranges for rectangles, and a measure landing after its test had finished once made Vitest exit 1 with every test green.
- `render.tsx` puts React on the page and takes every root off after each test.
- `fakeService.ts` is the account and sync service in memory, with the routes, revisions and refusals of `server/src/accounts.rs` and `server/src/sync.rs`, handed to the code as a `fetch`. `syncDevice.ts` is a device signed in to it.
- `stubs.ts` stands in for what jsdom lacks, one opt-in call each. There is deliberately no IntersectionObserver, because some components read its absence as an answer.
- `syntaxTree.ts` parses a test editor's whole note before anything is asserted, since CodeMirror parses on a time budget that a loaded machine misses.
- `notes.ts`, `boards.ts` and `canvas.ts` are shared notes, boards and canvases; `takeHost.ts` is a quiet host for the recorder's take, `battery.ts` a battery a test can drain, and `rows.ts` rows laid out on the page for the drag tests.

## Rust without Tauri

A full `cargo test --lib` builds the desktop windowing stack, llama.cpp and whisper.cpp before a single test runs, and fails on a Linux machine without the dbus headers. `tools/host-tests` is a small crate that compiles the real `note.rs`, `fsx.rs`, `store.rs` (the old store, kept for moving notes in), `library/mod.rs`, `llm/command.rs` and `llm/prompt.rs` by `#[path]`, with no copies and only their own dependencies. Run it with `cd tools/host-tests && cargo test`. It also keeps a promise honest: a `tauri::` type added to any of those files stops it compiling. It is not part of the report.

## Against a real server

Three end-to-end files run against a glyph-api on the same machine. Each is skipped unless its variable is set, makes a fresh account every run, and gives the whole command in its header.

| Set | File | What it proves |
|---|---|---|
| `GLYPH_SYNC_E2E`, the server's data folder | `src/app/core/sync/sync.e2e.test.ts` | Two devices on one account: notes, recordings and pictures carried across, edits and deletions both ways, both versions kept after a clash, and the server's own database read to show it never holds the words |
| `GLYPH_LIVE_E2E`, the same | `src/app/core/live/live.e2e.test.ts` | Two devices typing into one note through the relay, with real sockets and real sealing |
| `GLYPH_MCP_E2E=1` | `mcp/mcp.e2e.test.ts` | The built connector (after `node scripts/build-mcp.mjs`), spoken to over stdio as Claude speaks to it, beside a phone's sync; and the hosted bundle |

## Speech

`voice-tests/suite.json` is one short recording per feature, 92 of them, each with the notes it must leave. `npm run voice:text` writes it out as a script to record from, and `docs/VOICE_TESTS.md` is the manual.

- **From the scripts**, in every `npm test`: `src/app/capture/voiceSuite.test.ts` replays each line as one phrase with its silence after it, through the recorder's own logic (`src/app/capture/voiceSuite.ts`).
- **From the audio**, with `npm run voice:suite`: first the ignored Rust test `whisper::suite` hears each recording through the phone's streaming path and writes what it heard, then the same checks run on those words.

Know what a green suite proves. It drives the take a phrase at a time (`take.phrase` in `src/app/capture/take.ts`), the live reading of commands that the recorder no longer runs. So it holds the cues that `markdown.ts` lays out, and a command reader the app keeps dormant, with the tables, voice memos and boards that only that reader makes. What a recording does with a command at Done is held by other tests: `src/app/capture/instructionCorpus.json`, ten spoken commands with what each must come to, run with fixture answers standing in for the model, and the tests beside `finalInstruction.ts`, `instructionIntent.ts` and `instructionMutation.ts`. `docs/instruction-voice-commands.md` gives one command for the corpus and its neighbours.

`src/app/guide/guide.test.ts` holds the welcome guide's spoken examples (`src/app/guide/phrases.ts`) to the real rules. Each example is rendered and must still produce its mark, with no cue word left behind as text. A failure means a rule changed, and the welcome guide changes with it.

## The report

`scripts/test-report.mjs` runs the three suites, each to the end even when another fails, and writes `src/app/diag/testReport.generated.json`: every test's result, the counts, the version, the commit, whether the tree had changes, and a fingerprint of the source. The fingerprint (`scripts/testReport/source.mjs`) is a hash of every file under `src/`, `src-tauri/src/`, `server/src/` and `scripts/`, the report itself left out. `--only=vitest` or `--skip=cargo` runs part of it; a suite left out keeps its last results, marked not run.

A suite that ran no tests is an error, not a pass (`scripts/testReport/parse.mjs`): a runner that found nothing would otherwise show green.

The JSON is committed because the app compiles it in, so every release rewrites it. `vite.config.ts` stamps the same fingerprint into the build, and `src/app/diag/testReport.ts` compares the two. It reads the verdict from the suites themselves rather than trusting the report's own word.

The page is Settings › Test results, which appears in Developer mode (seven presses on the version in Settings › About). It gives a verdict ("Every test passed"), warns when the code changed after the tests ran, and lists each suite's tests by file with failures first and open, with a search and an Only failures switch.

`deploy-ota.mjs` runs the report before it builds and stops on a failure or a suite that did not run. With `--skip-tests` it ships with the last report in the tree, and when the code has changed since that report, the build's page says so: "From other code" in the list, and "The code changed after these tests ran. They are not this build’s results."

## The numbers

At 1.8.0-12, from the report in the tree: **3,046 of 3,169 tests passed, 123 were skipped, and none failed.**

| Suite | Passed | Skipped | Of |
|---|---|---|---|
| Page (Vitest) | 2,677 | 113 | 2,790 |
| App (Rust) | 223 | 10 | 233 |
| glyph-api (Rust) | 146 | 0 | 146 |

The 113 are the 92 voice tests from audio and the 21 end-to-end tests. The 10 load a real model or reach the network. Quote a count with its denominator.

## Before a commit

`npm run check` runs the lint, the typecheck (`tsc` for the app, then for `mcp/`) and the tests. Its lint is `eslint . --max-warnings 0`, which also finds other worktrees' copies of the repository and the plain scripts, so lint what you touched by path: `npx eslint <paths>`. Every rule `eslint.config.js` turns on is an error; there is no warning tier to hide in.

`npm run coverage` measures `src/app`, `src/read` and `mcp/*.ts`, and leaves out `mcp/dist`: the connector bundled into two files, whose 54,000 lines made three-quarters of the denominator and read the tree as 14% covered when the real figure was 57%.

## Read next

- [[Over the air, and releases]]
- [[Working on Ghost.md]]
- [[From microphone to Markdown]]
