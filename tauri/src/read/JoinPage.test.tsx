import { describe, expect, it } from 'vitest';
import { show } from '../test/render.tsx';
import { JoinPage } from './JoinPage.tsx';

/**
 * The page an invite link opens (docs/TEAMS.md): it knows nothing of the organization, and offers the app's own
 * scheme and the web app, each carrying the code, and the place to get the app.
 */

const CODE = 'AbCdEfGhIjKlMnOpQrSt_-';

describe('the invitation page', () => {
  it('offers the app and the web app, each with the code, and says nothing of the organization', () => {
    const host = show(<JoinPage code={CODE} />);
    expect(host.querySelector('h1')?.textContent).toBe('You’re invited to a team');
    const hrefs = [...host.querySelectorAll('a')].map((a) => [a.textContent, a.getAttribute('href')]);
    expect(hrefs).toContainEqual(['Open in the Ghost.md app', `ghostmd://join/${CODE}`]);
    const web = hrefs.find(([words]) => words === 'Join on the web')?.[1];
    expect(web).toMatch(new RegExp(`#join=${CODE}$`));
    expect(hrefs.some(([words]) => words === 'Get Ghost.md')).toBe(true);
  });
});
