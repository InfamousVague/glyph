import { describe, expect, it } from 'vitest';
import { failureText } from './failure.ts';

describe('a caught thing, as words', () => {
  it('reads an Error by its message, not its name', () => {
    expect(failureText(new Error('The note could not be saved.'))).toBe('The note could not be saved.');
    expect(failureText(new TypeError('x is undefined'))).toBe('x is undefined');
  });

  it('keeps the string a Tauri command rejects with, as Rust wrote it', () => {
    expect(failureText('busy: another capture is running')).toBe('busy: another capture is running');
  });

  it('turns anything else into text rather than failing to say anything', () => {
    expect(failureText(undefined)).toBe('undefined');
    expect(failureText(null)).toBe('null');
    expect(failureText(404)).toBe('404');
    expect(failureText({ toString: () => 'a thrown object' })).toBe('a thrown object');
  });

  it('answers an Error with an empty message as empty, not as its name', () => {
    expect(failureText(new Error(''))).toBe('');
  });
});
