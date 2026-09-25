import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { createIssue, NEEDS_TOKEN, readIssue, setIssueOpen } from './issues.ts';
import { setGithubToken } from './repos.ts';

/**
 * GitHub's issues API as the plugin calls it (issues.ts), stood in for by `fetch`: what is sent to make, read, close
 * and reopen an issue, the token that has to be there to write, and GitHub's refusals as sentences a person can act
 * on. Reading an issue's answer into a pill is issues.test.ts.
 */

const raw = (over: Record<string, unknown> = {}) => ({ number: 12, title: 'Ship the page', html_url: 'https://github.com/o/r/issues/12', state: 'open', labels: [], assignees: [], ...over });
const answer = (status: number, body: unknown) => new Response(JSON.stringify(body), { status, headers: { 'Content-Type': 'application/json' } });
const fetcher = vi.fn<typeof fetch>();

beforeEach(() => {
  localStorage.clear();
  fetcher.mockReset();
  // A fresh answer each time: a Response's body can be read once.
  fetcher.mockImplementation(async () => answer(200, raw()));
  vi.stubGlobal('fetch', fetcher);
});

afterEach(() => vi.unstubAllGlobals());

/** The one request made: its address, method, headers and body. */
function sent() {
  const [url, init] = fetcher.mock.calls[0]!;
  return { url: String(url), method: init?.method, headers: new Headers(init?.headers), body: init?.body ? JSON.parse(String(init.body)) : undefined };
}

describe('writing issues', () => {
  it('needs a token, and says where to add one, before asking GitHub anything', async () => {
    await expect(createIssue({ owner: 'o', repo: 'r' }, 'Ship it')).rejects.toThrow(NEEDS_TOKEN);
    await expect(setIssueOpen('https://github.com/o/r/issues/12', false)).rejects.toThrow(NEEDS_TOKEN);
    expect(fetcher).not.toHaveBeenCalled();
  });

  it('makes an issue with the item’s words, cut to what GitHub takes, and the token', async () => {
    setGithubToken('ghp_secret');
    const issue = await createIssue({ owner: 'o', repo: 'r' }, 'x'.repeat(300));
    const request = sent();
    expect(request.url).toBe('https://api.github.com/repos/o/r/issues');
    expect(request.method).toBe('POST');
    expect(request.headers.get('Authorization')).toBe('Bearer ghp_secret');
    expect(request.headers.get('Content-Type')).toBe('application/json');
    expect(request.body).toEqual({ title: 'x'.repeat(250) });
    expect(issue).toMatchObject({ owner: 'o', repo: 'r', number: 12, state: 'open' });
  });

  it('closes an issue as completed, and opens one again without a reason', async () => {
    setGithubToken('ghp_secret');
    await setIssueOpen('https://github.com/o/r/issues/12', false);
    expect(sent()).toMatchObject({ url: 'https://api.github.com/repos/o/r/issues/12', method: 'PATCH', body: { state: 'closed', state_reason: 'completed' } });
    fetcher.mockClear();
    await setIssueOpen('https://github.com/o/r/issues/12', true);
    expect(sent().body).toEqual({ state: 'open' });
  });
});

describe('reading issues', () => {
  it('reads one without a token, and refuses an address that is not an issue', async () => {
    await readIssue('https://github.com/o/r/issues/12');
    const request = sent();
    expect(request.method).toBe('GET');
    expect(request.headers.get('Authorization')).toBeNull();
    expect(request.headers.get('Content-Type')).toBeNull();
    await expect(readIssue('https://github.com/o/r/pull/3')).rejects.toThrow('That isn’t a GitHub issue.');
  });
});

describe('GitHub’s refusals', () => {
  it('are said as what a person can do about them', async () => {
    setGithubToken('ghp_secret');
    const refusal = async (status: number, message: string, call: () => Promise<unknown>) => {
      fetcher.mockResolvedValueOnce(answer(status, { message }));
      return call().then(
        () => 'no refusal',
        (failure: Error) => failure.message,
      );
    };
    const read = () => readIssue('https://github.com/o/r/issues/12');
    const write = () => createIssue({ owner: 'o', repo: 'r' }, 'Ship it');
    expect(await refusal(401, 'Bad credentials', read)).toBe('GitHub didn’t accept that token. Check it in Settings > Plugins > GitHub.');
    expect(await refusal(403, 'API rate limit exceeded for 1.2.3.4', read)).toBe('GitHub is rate limiting this phone. Try again in a few minutes.');
    expect(await refusal(404, 'Not Found', read)).toBe('That issue isn’t readable with this token.');
    expect(await refusal(403, 'Resource not accessible by integration', write)).toBe('That repo doesn’t allow this token to write issues.');
    expect(await refusal(410, 'Issues are disabled for this repo', write)).toBe('Issues are switched off for that repo.');
    expect(await refusal(422, 'Validation Failed', write)).toBe('GitHub: Validation Failed');
    fetcher.mockResolvedValueOnce(new Response('upstream', { status: 502 }));
    await expect(write()).rejects.toThrow('GitHub answered 502.');
  });
});
