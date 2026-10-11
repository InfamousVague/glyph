import type { QueryNote } from './records.ts';

/*
 * A small library for the query's tests (core/query/*.test.ts): a notebook of tickets with the key GHO, a shopping
 * list of to-dos with fields, a note with tags, and a note that links to a ticket. "Today" in these tests is
 * Monday 5 October 2026.
 */

export const TODAY = '2026-10-05';

const at = (day: string) => new Date(`${day}T12:00:00`).getTime();
const note = (id: string, body: string, updated: string, created = '2026-09-01'): QueryNote => ({ id, body, createdAt: at(created), updatedAt: at(updated) });

export const NOTES: QueryNote[] = [
  note('launch', '---\ntitle: "Launch"\nbook: true\nkey: GHO\n---\n# Launch\n\n- [[Fix the login loop]]\n- [[Pricing page]]\n- [[Dark mode]]\n', '2026-09-20'),
  note(
    'gho1',
    '---\ntype: ticket\nid: GHO-1\nstatus: In progress\nassignee: Sam\npriority: high\ndue: 2026-10-03\nstart: 2026-09-28\nestimate: 3\nlabels: [bug, auth]\n---\n# Fix the login loop\n\nThe token is refreshed twice.\n\n- [ ] Write the failing test 📅 2026-10-06\n',
    '2026-10-04',
  ),
  note('gho2', '---\ntype: ticket\nid: GHO-2\nstatus: To do\nassignee: Alex\npriority: highest\ndue: 2026-10-10\nestimate: 5\nblocked-by: "[[GHO-1]]"\n---\n# Pricing page\n', '2026-10-02'),
  note('gho3', '---\ntype: ticket\nid: GHO-3\nstatus: Done\npriority: low\nestimate: 2\n---\n# Dark mode\n', '2026-09-25'),
  note(
    'shop',
    '---\ntags: [errands]\n---\n# Groceries\n\n- [ ] Milk 📅 2026-10-04 @sam #dairy\n- [x] Eggs ✅ 2026-10-01\n- [ ] Bread ⏫ 📅 2026-10-05\n- [ ] Coffee beans [cost:: $12]\n- [ ] Butter [cost:: $4.50] @alex\n- [ ]\n\n```\n- [ ] not a to-do, it is code\n```\n',
    '2026-10-05',
  ),
  note('ideas', '# Book ideas\n\nA ghost who writes notes #writing/fiction for people who forget.\n', '2026-08-01'),
  note('standup', '# Standup\n\nWe talked about [[GHO-1]] and the [[Pricing page]].\n', '2026-10-01'),
];
