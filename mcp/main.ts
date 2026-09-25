import { failureWords, runCli } from './cli.ts';

/**
 * The `glyph-mcp` command's entry point (docs/MCP.md): what scripts/build-mcp.mjs bundles into mcp/dist/glyph-mcp.mjs,
 * and what Claude Desktop, Claude Code and the rest start. It runs the command (mcp/cli.ts) with this process's
 * arguments, environment and terminal, and says any failure in one line and exits 1.
 */

runCli(process.argv.slice(2), {
  env: process.env,
  stdin: process.stdin,
  out: (words) => process.stdout.write(words),
  err: (words) => process.stderr.write(words),
}).catch((failure: unknown) => {
  process.stderr.write(`glyph-mcp: ${failureWords(failure)}\n`);
  process.exit(1);
});
