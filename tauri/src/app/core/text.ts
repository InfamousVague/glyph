/**
 * The small things done to a string all over the app, done one way.
 *
 * Spoken words arrive in lower case and are written as a person would write
 * them, so a title, a list item or a plugin's name is capitalised where it is
 * shown - fifteen places did that by hand - and a tip read aloud after "Hey
 * Ghost," goes the other way. Words a person said, or a key they chose, are
 * searched for inside a pattern, which means escaping them first; six places
 * wrote the same character class for that.
 *
 * Deliberately only the first letter: "iPhone" and "API" keep their own
 * spelling after the first character, because what came after it is what
 * the person said. A leaf with no imports, so anything may use it, the MCP
 * server included.
 */

/** `text` with its first character in upper case and the rest as written: "milk" -> "Milk". */
export function capitalise(text: string): string {
  return text.charAt(0).toUpperCase() + text.slice(1);
}

/** `text` with its first character in lower case and the rest as written: "Add milk" -> "add milk". */
export function lowerFirst(text: string): string {
  return text.charAt(0).toLowerCase() + text.slice(1);
}

/** `text` with every character a RegExp reads as syntax escaped, so a pattern built around it matches it literally. */
export function escapeRegExp(text: string): string {
  return text.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}
