// Publishing a note or a notebook as a site (lib/share/sites.dart): sealed under the site's own key in its own
// context, the notebook's pages in its order with nothing of where they were written, published again at the same
// address, listed on every device of the account by what it sealed beside the site under the account key, and
// unpublished. Over the service in memory and the fake crypto.
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/share/share.dart';
import 'package:ghost_md/share/sites.dart';

import '../account_ui/support.dart';

const String index = '---\ntitle: "Field guide"\nbook: true\n---\n# Field guide\n\n1. [[Trees]]\n2. [[Birds]]\n3. [[Not yet]]\n';
const String trees = '---\nlocation: 51.5074,-0.1278\n---\n# Trees\n\nOaks, by [Cais do Sodré, Lisbon](geo:38.7061,-9.1443). See [[Birds]].';
const String birds = '# Birds\n\nRobins.';

void main() {
  test('a notebook is published whole, in its order, with nothing of where its pages were written', () async {
    final device = await Device.make(publishing: true);
    final book = device.keep('book', index);
    device.keep('t', trees);
    device.keep('b', birds);
    final site = await device.sites!.publish(book, device.notes.held.values.toList());
    expect(site.link, 'https://ghostmarkdown.com/s/${site.id}#${site.key}');
    expect((site.title, site.kind, site.noteId), ('Field guide', 'book', 'book'));
    expect(device.service.sites.keys, [site.id]);
    final read = await device.sites!.readSite(site.id, site.key);
    expect(read.kind, 'book');
    expect(read.pages.map((p) => p.title), ['Field guide', 'Trees', 'Birds'], reason: 'the index, then each page that has a note, in order');
    expect(read.pages[1].body, isNot(contains('51.5074')));
    expect(read.pages[1].body, isNot(contains('geo:')));
    expect(read.pages[1].body, contains('[[Birds]]'));
    // Sealed in a site's own context: it does not open as a share.
    await expectLater(openShare(device.service.crypto, device.service.sites[site.id]!.blob, site.key), throwsA(anything));
  });

  test('published again it keeps its address, moves "last published", and carries the edits', () async {
    var clock = 1000;
    final service = await FakeService.start(seed: seeded)..clock = () => clock;
    final device = await Device.make(service: service, publishing: true);
    final note = device.keep('n', '# Walk\n\nBy the river.');
    final first = await device.sites!.publish(note, device.notes.held.values.toList());
    clock = 5000;
    final edited = device.keep('n', '# Walk\n\nBy the river, then the hill.');
    final again = await device.sites!.publish(edited, device.notes.held.values.toList());
    expect((again.id, again.key, again.created, again.updated), (first.id, first.key, 1000, 5000));
    expect(device.sites!.list, hasLength(1));
    expect((await device.sites!.readSite(again.id, again.key)).pages.single.body, contains('the hill'));
  });

  test('another device of the account lists the site with its link, from what was sealed beside it', () async {
    final service = await FakeService.start(seed: seeded);
    final phone = await Device.make(service: service, publishing: true);
    final note = phone.keep('n', '# Walk');
    final site = await phone.sites!.publish(note, phone.notes.held.values.toList());
    final mac = await Device.make(service: service, publishing: true);
    expect(mac.sites!.read, isFalse);
    final listed = await mac.sites!.refresh();
    expect(listed.map((s) => (s.id, s.key, s.noteId, s.title)), [(site.id, site.key, 'n', 'Walk')]);
    expect(mac.sites!.siteFor('n')?.link, site.link);
    // The service holds the key only sealed.
    expect(service.sites[site.id]!.meta, isNot(contains(site.key)));
    await mac.sites!.unpublish(listed.single);
    expect(service.sites, isEmpty);
    expect(mac.sites!.siteFor('n'), isNull);
  });

  test('a site the device cannot read is counted, signing out forgets the list, and signed out nothing is published', () async {
    final service = await FakeService.start(seed: seeded);
    final device = await Device.make(service: service, publishing: true);
    service.sites['from-a-newer-app-000001'] = (blob: 'eA', meta: 'bm90IHNlYWxlZA', created: 1, updated: 1);
    await device.sites!.refresh();
    expect((device.sites!.list.length, device.sites!.unread), (0, 1));
    await device.account.signOut();
    expect((device.sites!.read, device.sites!.unread), (false, 0));
    await expectLater(device.sites!.publish(device.keep('n', '# A'), const []), throwsA(predicate((e) => '$e'.contains('Sign in under Settings'))));
  });

  test('a site is offered everywhere but the iPhone', () {
    expect(publishingOffered(TargetPlatform.android), isTrue);
    expect(publishingOffered(TargetPlatform.macOS), isTrue);
    expect(publishingOffered(TargetPlatform.iOS), isFalse);
  });
}
