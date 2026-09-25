import { describe, expect, it } from 'vitest';
import { appendBlock, appendBody } from './appendBody.ts';

describe('words on the end of a note', () => {
  it('puts a recording under the note it continues, one blank line between, and nothing for nothing said', () => {
    expect(appendBody('# Trip\n\nBook the cabin.\n\n', 'Ask Sam.')).toBe('# Trip\n\nBook the cabin.\n\nAsk Sam.');
    expect(appendBody('', 'Ask Sam.')).toBe('Ask Sam.');
    expect(appendBody('# Trip', '  \n')).toBe('# Trip');
  });

  it('ends a block of its own with a line break, and starts an empty note with it', () => {
    expect(appendBlock('# Bugbash\n\nFriday.\n', '| A |\n| --- |')).toBe('# Bugbash\n\nFriday.\n\n| A |\n| --- |\n');
    expect(appendBlock('  \n', '- Milk')).toBe('- Milk\n');
  });
});
