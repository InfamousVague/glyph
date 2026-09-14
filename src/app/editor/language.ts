import { markdown, markdownLanguage } from '@codemirror/lang-markdown';
import type { Extension } from '@codemirror/state';

/**
 * The markdown the editor speaks: GFM, with one CommonMark rule taken out.
 *
 * In CommonMark a line of dashes or equals signs under a paragraph turns the
 * paragraph into a heading (a "setext" heading). On a phone that rule bites:
 * typing `-` to start a list under a line promoted the line above it, and the
 * person was "stuck in headings". Here `#` is the only way to make a heading;
 * a lone `-` is an empty list item and `---` is a rule. Kept in its own module
 * so the parser can be tested without a view.
 */
export function glyphMarkdown(): Extension {
  return markdown({
    // GFM: the default `commonmarkLanguage` has no strikethrough and no task
    // lists, both of which a notes app wants.
    base: markdownLanguage,
    extensions: [{ remove: ['SetextHeading'] }],
    // Enter continues a list, Backspace removes a marker whole. The most
    // useful phone behaviour in the package.
    addKeymap: true,
    // No autocomplete popup over a phone keyboard when a `<` is typed.
    completeHTMLTags: false,
    pasteURLAsLink: true,
  });
}
