import { describe, expect, it } from 'vitest';
import { ApiError, notYet } from './api.ts';

describe('a 404 that means "not yet"', () => {
  it('is the service’s own "no such route", or a 404 with no service body', () => {
    expect(notYet(new ApiError(404, 'no such route', { error: 'no such route' }))).toBe(true);
    expect(notYet(new ApiError(404, 'The sync service answered 404.', null))).toBe(true);
    expect(notYet(new ApiError(404, 'The sync service answered 404.', '<html>not found</html>'))).toBe(true);
  });

  it('is never a 404 in the service’s words, which is an answer, nor any other status', () => {
    expect(notYet(new ApiError(404, 'No one has that handle.', { error: 'No one has that handle.' }))).toBe(false);
    expect(notYet(new ApiError(404, 'You were not invited.', { error: 'You were not invited.' }))).toBe(false);
    expect(notYet(new ApiError(500, 'no such route', { error: 'no such route' }))).toBe(false);
    expect(notYet(new ApiError(0, 'The sync service could not be reached.'))).toBe(false);
    expect(notYet(new Error('not a refusal'))).toBe(false);
    expect(notYet('404')).toBe(false);
  });

  it('reads another error class that carries a status and a body, as the MCP server’s does', () => {
    class Other extends Error {
      constructor(
        readonly status: number,
        readonly body: unknown,
      ) {
        super('other');
      }
    }
    expect(notYet(new Other(404, { error: 'no such route' }))).toBe(true);
    expect(notYet(new Other(404, { error: 'No such organization.' }))).toBe(false);
  });
});
