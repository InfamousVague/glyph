/**
 * How a note refers to a picture: `![caption](image/<name>)`, a relative path, so a folder of notes with an `image/`
 * folder beside it still makes sense anywhere Markdown is read (core/images.ts says where the pictures themselves
 * are kept).
 *
 * Only the words, and nothing that reaches for a picture: core/images.ts imports the Tauri bridge at its top, which
 * the MCP server's Node bundle cannot take, so the server kept a copy of the pattern and of `imageNames` (mcp/glyph.ts)
 * to name the pictures a note it writes carries. This module imports nothing, so the server and the app read a
 * body's pictures with the same code; core/images.ts re-exports all three for its callers.
 */

/** A picture's reference in a body: the caption, then the name, as groups 1 and 2. Global, so read it with `matchAll`. */
export const IMAGE_REF = /!\[([^\]]*)\]\(image\/([A-Za-z0-9_.-]+)\)/g;

/** The markdown for a picture, on a line of its own. */
export function imageMarkdown(name: string, caption = ''): string {
  return `![${caption}](image/${name})`;
}

/** Every picture a note refers to. */
export function imageNames(body: string): string[] {
  return [...body.matchAll(IMAGE_REF)].map((m) => m[2] ?? '').filter(Boolean);
}
