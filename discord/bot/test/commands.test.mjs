// `/ghost` as Discord is told of it (lib/commands.mjs), and what the bot says (lib/words.mjs): who asked and that
// the call is recorded, in the channel's chat; names as text, never a ping or markdown.
import assert from 'node:assert/strict';
import { test } from 'node:test';
import { COMMANDS, subcommandOf } from '../lib/commands.mjs';
import { announce, clean, leftBecause, newcomer } from '../lib/words.mjs';

test('one command, three subcommands, in servers only; link takes its code', () => {
  assert.equal(COMMANDS.length, 1);
  const [ghost] = COMMANDS;
  assert.equal(ghost.name, 'ghost');
  assert.deepEqual(ghost.contexts, [0]);
  assert.deepEqual(ghost.options.map((o) => [o.type, o.name]), [[1, 'join'], [1, 'leave'], [1, 'link']]);
  const [code] = ghost.options[2].options;
  assert.deepEqual([code.type, code.name, code.required], [3, 'code', true]);
  for (const o of [ghost, ...ghost.options]) assert.ok(o.description.length > 0 && o.description.length <= 100, o.name);
});

test('an interaction is read as its subcommand, or as nothing of ours', () => {
  const as = (name, sub, chat = true) => ({ isChatInputCommand: () => chat, commandName: name, options: { getSubcommand: () => sub } });
  assert.equal(subcommandOf(as('ghost', 'join')), 'join');
  assert.equal(subcommandOf(as('ghost', 'link')), 'link');
  assert.equal(subcommandOf(as('other', 'join')), null);
  assert.equal(subcommandOf(as('ghost', 'join', false)), null);
  assert.equal(subcommandOf(as('ghost', 'dance')), null);
  assert.equal(subcommandOf(null), null);
});

test('the notice names who asked, says it is recorded and how to stop it', () => {
  const said = announce('Sam Lee');
  assert.match(said, /Ghost is taking notes for Sam Lee/);
  assert.match(said, /recorded/);
  assert.match(said, /\/ghost leave/);
  assert.match(newcomer('Ali', 'Sam Lee'), /^Ali, Ghost is recording this call for Sam Lee/);
  assert.equal(leftBecause('shutdown'), null);
  assert.match(leftBecause('alone'), /left/);
});

test('a name is plain text: no markdown, no mention, not too long', () => {
  assert.equal(clean('**Sam** <@123> `x`'), 'Sam 123 x');
  assert.equal(clean('@everyone'), 'everyone');
  assert.equal(clean(''), 'someone');
  assert.equal(clean('a'.repeat(200)).length, 80);
});
