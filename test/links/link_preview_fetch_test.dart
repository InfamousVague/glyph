// The read behind a link's card: src-tauri/src/link_preview.rs's three tests, case for case, then the read itself
// against a server on 127.0.0.1, and the address check as a pure function. core/linkPreview.test.ts (what is kept,
// when it is asked again) is ported in test/editor/media/core_test.dart; its last case, opening a link, is in
// open_link_test.dart. Nothing here leaves this machine: the one case that would is skipped unless asked for by hand.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/link_preview.dart';

LinkPreview head(String html) => readHead(html, 'https://x.dev');

/// A server on 127.0.0.1 that answers with [answer], and what it was asked.
class Site {
  Site._(this.server);

  final HttpServer server;
  final List<HttpRequest> asked = <HttpRequest>[];

  static Future<Site> start(FutureOr<void> Function(HttpRequest request) answer) async {
    final site = Site._(await HttpServer.bind(InternetAddress.loopbackIPv4, 0));
    site.server.listen((request) async {
      site.asked.add(request);
      try {
        await answer(request);
      } catch (_) {
        // The reader hung up, as it does once the head has closed.
      }
    });
    addTearDown(() => site.server.close(force: true));
    return site;
  }

  int get port => server.port;
  String get base => 'http://127.0.0.1:$port';

  /// Admits this server and nothing else.
  bool allow(InternetAddress address, int port) => address.address == '127.0.0.1' && port == this.port;

  LinkPreviewFetch fetch({HostResolver? resolve, Duration timeout = const Duration(seconds: 20), int maxBytes = linkPreviewMaxBytes, int maxRedirects = linkPreviewMaxRedirects}) =>
      linkPreviewFetch(allow: allow, resolve: resolve, timeout: timeout, maxBytes: maxBytes, maxRedirects: maxRedirects);
}

Future<void> html(HttpRequest request, String page, {String type = 'text/html; charset=utf-8'}) async {
  request.response.headers.set('content-type', type);
  request.response.write(page);
  await request.response.close();
}

Matcher refusedWith(String message) => throwsA(isA<LinkPreviewError>().having((error) => error.message, 'message', message));
const String unreached = "The page couldn't be reached.";

void main() {
  group('link_preview.rs', () {
    test('prefers_open_graph_and_falls_back_to_the_title', () {
      const page = '''<html><head><title>Plain &amp; simple</title>
            <meta property="og:title" content="The  Cabin&#39;s Page">
            <META NAME='description' content="A place &mdash; in the woods">
            <meta property="og:site_name" content=Airbnb></head><body><title>not this</title></body>''';
      final p = head(page);
      expect(p.title, "The Cabin's Page");
      expect(p.site, 'Airbnb');
      expect(p.description, 'A place — in the woods');

      final bare = head('<head><title>\n  Just a title \n</title></head>');
      expect(bare.title, 'Just a title');
      expect(bare.site, isNull);
      expect(bare.description, isNull);
    });

    test('copes_with_odd_markup_and_long_text', () {
      final p = head('<meta content="Content first" property="og:title"/><meta name="description" content="">');
      expect(p.title, 'Content first');
      expect(p.description, isNull, reason: 'an empty description is none');
      final long = '<title>${'word ' * 200}</title>';
      expect(head(long).title!.runes.length, lessThanOrEqualTo(linkPreviewMaxChars));
      expect(head(long).title, endsWith('word…'));
      expect(head('<p>no head at all').title, isNull);
      expect(decodeEntities('a & b &unknown; &#x1F389;'), 'a & b &unknown; 🎉');
    });

    test('a_tag_ends_at_its_own_close_not_at_one_inside_its_quotes', () {
      final p = head('''<meta property="og:title" content="1 > 0, and it's 'quoted'"/><meta name=description content=bare>''');
      expect(p.title, "1 > 0, and it's 'quoted'");
      expect(p.description, 'bare', reason: 'an unquoted value runs to the next space or the close');
      expect(tagEnd(''' a="x>y" b='>'>rest'''), 14);
      expect(tagEnd(' never closed'), 13, reason: 'a tag that never closes runs to the end');
      expect(tagAttributes(''' A="1" b c = '2' /'''), <(String, String)>[('a', '1'), ('b', ''), ('c', '2')]);
    });
  });

  group('a page’s head', () {
    test('takes the first of each tag, og: before twitter: before the title, og:description before description', () {
      final p = head('<head><meta name="twitter:title" content="Tweeted"><meta property="og:title" content="First"><meta property="og:title" content="Second">'
          '<meta name="description" content="Plain"><meta property="og:description" content="Graphed"><title>Tagged</title></head>');
      expect(p.title, 'First');
      expect(p.description, 'Graphed');
      expect(head('<meta name="twitter:title" content="Tweeted"><title>Tagged</title>').title, 'Tweeted');
      expect(head('<meta NAME="OG:Title" content="Shouted">').title, 'Shouted', reason: 'the key is read without its case');
      expect(head('<title></title>').title, isNull, reason: 'an empty title is none');
      expect(head('<title>never closed').title, isNull);
      expect(head('<TITLE lang="en">Upper</TITLE>').title, 'Upper');
    });

    test('reads nothing past the head’s close', () {
      expect(head('<head></HEAD><meta property="og:title" content="In the body"><title>Body</title>').title, isNull);
    });

    test('decodes the entities it knows and leaves the rest', () {
      expect(decodeEntities('&lt;b&gt; &quot;q&quot; &apos;a&apos; &#39; x&nbsp;y &ndash; &hellip; &#65;&#x42;&#X43;'), '<b> "q" \'a\' \' x y – … ABC');
      expect(decodeEntities('&#xD800; &#1114112; &#; &#x; &#-65; &# 65; &'), '&#xD800; &#1114112; &#; &#x; &#-65; &# 65; &', reason: 'not a character: left as written');
      expect(decodeEntities('&averyveryverylongname; &amp;'), '&averyveryverylongname; &', reason: 'no ; within twelve: not an entity');
    });
  });

  group('an address the read may go to', () {
    bool public(String address) => isPublicAddress(InternetAddress(address));

    test('is anywhere on the internet', () {
      for (final address in const <String>['1.1.1.1', '8.8.8.8', '93.184.216.34', '172.15.255.255', '172.32.0.1', '192.167.1.1', '192.169.1.1', '100.63.255.255', '100.128.0.1', '169.253.1.1', '223.255.255.254', '11.0.0.1', '126.255.255.255', '128.0.0.1', '198.17.0.1', '198.20.0.1', '2606:4700:4700::1111', '2a00:1450:4001:81b::200e', '2001:4860:4860::8888', '::ffff:8.8.8.8', '64:ff9b::808:808', '2002:808:808::1']) {
        expect(public(address), isTrue, reason: address);
      }
    });

    test('is never this device, its network, or nowhere', () {
      const refused = <String>[
        // loopback
        '127.0.0.1', '127.1.2.3', '127.255.255.255', '::1',
        // private
        '10.0.0.1', '10.255.255.255', '172.16.0.1', '172.20.10.5', '172.31.255.255', '192.168.0.1', '192.168.255.255',
        // link-local, and the cloud's metadata address in it
        '169.254.0.1', '169.254.169.254', 'fe80::1', 'febf::1', 'fec0::1',
        // unique-local
        'fc00::1', 'fd12:3456:789a::1', 'fdff:ffff:ffff:ffff:ffff:ffff:ffff:ffff',
        // unspecified, and "this network"
        '0.0.0.0', '0.1.2.3', '::',
        // multicast, reserved, broadcast
        '224.0.0.1', '239.255.255.250', '240.0.0.1', '255.255.255.255', 'ff02::1', 'ff0e::1',
        // a carrier's shared space, protocol assignments, benchmarking
        '100.64.0.1', '100.127.255.255', '192.0.0.1', '198.18.0.1', '198.19.255.255',
        // IPv6 forms carrying an IPv4 address that is one of those
        '::ffff:127.0.0.1', '::ffff:10.0.0.1', '::ffff:192.168.1.1', '::ffff:169.254.169.254', '::ffff:172.16.0.1', '::ffff:0.0.0.0', '::ffff:224.0.0.1',
        '::127.0.0.1', '::10.0.0.1', '64:ff9b::7f00:1', '64:ff9b::a00:1', '64:ff9b:1::1', '2002:7f00:1::1', '2002:c0a8:101::1', '2002:a00:1::1',
        // Teredo
        '2001:0:4136:e378:8000:63bf:3fff:fdd2',
      ];
      for (final address in refused) {
        expect(public(address), isFalse, reason: address);
      }
    });

    test('is a web address: http or https, with a site', () {
      expect(linkPreviewAddress('  https://example.com/a  ').toString(), 'https://example.com/a');
      expect(linkPreviewAddress('HTTP://Example.com').scheme, 'http');
      for (final url in const <String>['example.com', '', 'not a url', 'http://', 'https:///path']) {
        expect(() => linkPreviewAddress(url), refusedWith("That isn't a web address."), reason: url);
      }
      for (final url in const <String>['mailto:a@b.c', 'file:///etc/passwd', 'ftp://example.com/', 'javascript:alert(1)', 'content://media/1', 'geo:1,2', 'data:text/html,hi']) {
        expect(() => linkPreviewAddress(url), refusedWith('Only web pages have previews.'), reason: url);
      }
    });
  });

  group('reading a page', () {
    test('answers its title, site name and summary, asked as the app asks', () async {
      final site = await Site.start((request) => html(request, '<html><head><title>Plain</title><meta property="og:title" content="A cabin &amp; a lake"><meta property="og:site_name" content="Airbnb"><meta name="description" content="In the woods"></head><body></body></html>'));
      final preview = await site.fetch()('${site.base}/rooms/1234?x=1');
      expect(preview, LinkPreview(url: '${site.base}/rooms/1234?x=1', title: 'A cabin & a lake', site: 'Airbnb', description: 'In the woods'));
      final asked = site.asked.single;
      expect(asked.method, 'GET');
      expect(asked.uri.toString(), '/rooms/1234?x=1');
      expect(asked.headers.value('user-agent'), 'Mozilla/5.0 (compatible; GlyphLinkPreview/1.0)');
      expect(asked.headers.value('accept'), 'text/html,application/xhtml+xml;q=0.9,*/*;q=0.1');
      expect(asked.headers.value('referer'), isNull);
      expect(asked.headers.value('cookie'), isNull);
    });

    test('names the site by its address, without www, when the page does not', () async {
      final site = await Site.start((request) => html(request, '<title>Only a title</title>'));
      Future<List<InternetAddress>> resolve(String host) async => <InternetAddress>[InternetAddress.loopbackIPv4];
      expect(await site.fetch()(site.base), LinkPreview(url: site.base, title: 'Only a title', site: '127.0.0.1'));
      final named = await site.fetch(resolve: resolve)('http://www.cabins.test:${site.port}/');
      expect(named.site, 'cabins.test');
      // The socket went to the address that was checked, and the request still names the site.
      expect(site.asked.last.headers.value('host'), 'www.cabins.test:${site.port}');
    });

    test('stops reading where the head closes', () async {
      final never = Completer<void>();
      addTearDown(never.complete);
      final site = await Site.start((request) async {
        request.response.bufferOutput = false; // dart:io's server keeps a small body back otherwise, flush or not
        request.response.headers.set('content-type', 'text/html');
        request.response.write('<head><title>Early</title></head>');
        await request.response.flush();
        await never.future; // a body that never ends
      });
      expect((await site.fetch()(site.base)).title, 'Early');
    });

    test('reads no more than the limit of a body', () async {
      final filler = '<!-- ${'x' * 1000} -->\n';
      final site = await Site.start((request) async {
        request.response.headers.set('content-type', 'text/html');
        request.response.write('<html><head>');
        for (var i = 0; i < 600; i++) {
          request.response.write(filler);
        }
        request.response.write('<title>Past the limit</title></head>');
        await request.response.close();
      });
      final preview = await site.fetch()(site.base);
      expect(preview.title, isNull, reason: 'the title is past the first half megabyte');
      expect(preview.site, '127.0.0.1');
      expect((await site.fetch(maxBytes: 2 * 1024 * 1024)(site.base)).title, 'Past the limit', reason: 'the page does have one');
      // The cut is at the byte: a title that straddles it is not a title.
      final cut = await Site.start((request) => html(request, '<title>abcdef</title>'));
      expect((await cut.fetch(maxBytes: 10)(cut.base)).title, isNull);
      expect((await cut.fetch(maxBytes: 21)(cut.base)).title, 'abcdef');
    });

    test('follows five redirects by hand, and not a sixth', () async {
      final site = await Site.start((request) async {
        final left = int.parse(request.uri.pathSegments.last);
        if (left == 0) return html(request, '<title>Arrived</title>');
        // A relative address, a different status each hop.
        request.response.statusCode = const <int>[301, 302, 303, 307, 308][left % 5];
        request.response.headers.set('location', left.isEven ? '../hop/${left - 1}' : '/hop/${left - 1}');
        await request.response.close();
      });
      final five = await site.fetch()('${site.base}/hop/5');
      expect(five.title, 'Arrived');
      expect(five.url, '${site.base}/hop/0', reason: 'the address answered is where it ended');
      expect(site.asked.length, 6);
      site.asked.clear();
      await expectLater(site.fetch()('${site.base}/hop/6'), refusedWith(unreached));
      expect(site.asked.length, 6, reason: 'the sixth redirect is not followed');
      expect((await site.fetch(maxRedirects: 1)('${site.base}/hop/1')).title, 'Arrived');
      await expectLater(site.fetch(maxRedirects: 1)('${site.base}/hop/2'), refusedWith(unreached));
    });

    test('refuses a redirect to a private address, to a name that resolves to one, and to what is not a web page', () async {
      var to = '';
      final site = await Site.start((request) async {
        if (request.uri.path == '/inside') return html(request, '<title>The router</title>');
        request.response.statusCode = 302;
        request.response.headers.set('location', to);
        await request.response.close();
      });
      final checked = <String>[];
      final looked = <String>[];
      bool allow(InternetAddress address, int port) {
        checked.add('${address.address}:$port');
        return site.allow(address, port) || (isPublicAddress(address));
      }

      Future<List<InternetAddress>> resolve(String host) async {
        looked.add(host);
        return switch (host) {
          'router.test' => <InternetAddress>[InternetAddress('192.168.1.1')],
          'both.test' => <InternetAddress>[InternetAddress('93.184.216.34'), InternetAddress('10.0.0.7')],
          'mapped.test' => <InternetAddress>[InternetAddress('::ffff:127.0.0.1')],
          'nowhere.test' => <InternetAddress>[],
          _ => throw const SocketException('no such host'),
        };
      }

      final fetch = linkPreviewFetch(allow: allow, resolve: resolve, timeout: const Duration(seconds: 20));
      for (final target in const <String>['http://10.0.0.1/admin', 'http://192.168.1.1/', 'http://169.254.169.254/latest/meta-data/', 'http://[::1]/', 'http://[fd00::1]/', 'http://0.0.0.0/', 'http://[::ffff:10.0.0.1]/']) {
        to = target;
        await expectLater(fetch(site.base), refusedWith(unreached), reason: target);
      }
      expect(checked, containsAll(<String>['10.0.0.1:80', '192.168.1.1:80', '169.254.169.254:80', '::1:80', 'fd00::1:80', '0.0.0.0:80']));
      expect(looked, isEmpty, reason: 'an address written as numbers is not looked up');
      for (final target in const <String>['http://router.test/', 'http://both.test/', 'http://mapped.test/', 'http://nowhere.test/', 'http://unknown.test/']) {
        to = target;
        await expectLater(fetch(site.base), refusedWith(unreached), reason: target);
      }
      expect(looked, <String>['router.test', 'both.test', 'mapped.test', 'nowhere.test', 'unknown.test']);
      for (final target in const <String>['file:///etc/passwd', 'ftp://example.com/x', 'javascript:alert(1)', 'content://media/1', 'intent://x#Intent;end']) {
        to = target;
        await expectLater(fetch(site.base), refusedWith(unreached), reason: target);
      }
      // Another port of this machine is as private as the rest of it.
      to = 'http://127.0.0.1:${site.port + 1}/';
      await expectLater(site.fetch()(site.base), refusedWith(unreached));
      expect(site.asked.every((request) => request.uri.path != '/inside'), isTrue);
    });

    test('never asks this machine or a private address with the app’s own check', () async {
      final site = await Site.start((request) => html(request, '<title>Private</title>'));
      final fetch = linkPreviewFetch(resolve: (host) async => <InternetAddress>[InternetAddress.loopbackIPv4]);
      for (final url in <String>['${site.base}/', 'http://[::ffff:127.0.0.1]:${site.port}/', 'http://rebound.test:${site.port}/']) {
        await expectLater(fetch(url), refusedWith(unreached), reason: url);
      }
      // The app's own resolver too: this machine's name for itself.
      await expectLater(linkPreviewFetch()('http://localhost:${site.port}/'), refusedWith(unreached));
      expect(site.asked, isEmpty);
    });

    test('connects to the address that was checked, with one lookup a hop', () async {
      final site = await Site.start((request) => html(request, '<title>Pinned</title>'));
      var lookups = 0;
      // A name that answers this server once and somewhere else ever after (a rebinding name).
      Future<List<InternetAddress>> resolve(String host) async => <InternetAddress>[++lookups == 1 ? InternetAddress.loopbackIPv4 : InternetAddress('10.0.0.1')];
      expect((await site.fetch(resolve: resolve)('http://rebind.test:${site.port}/')).title, 'Pinned');
      expect(lookups, 1);
    });

    test('answers only the site for what is not HTML, and reads a page that does not say what it is', () async {
      final site = await Site.start((request) async {
        if (request.uri.path == '/untyped') {
          request.response.headers.removeAll('content-type');
          request.response.headers.contentType = null;
          request.response.write('<title>Untyped</title>');
          return request.response.close();
        }
        return html(request, '<title>Not read</title>', type: request.uri.path == '/json' ? 'application/json' : 'image/png');
      });
      expect(await site.fetch()('${site.base}/cat.png'), LinkPreview(url: '${site.base}/cat.png', site: '127.0.0.1'));
      expect((await site.fetch()('${site.base}/json')).title, isNull);
      final untyped = await site.fetch()('${site.base}/untyped');
      expect(site.asked.last.response.headers.value('content-type'), isNull);
      expect(untyped.title, 'Untyped');
      final xhtml = await Site.start((request) => html(request, '<title>X</title>', type: 'application/xhtml+xml'));
      expect((await xhtml.fetch()(xhtml.base)).title, 'X');
    });

    test('says what the page answered when it was not a success', () async {
      final site = await Site.start((request) async {
        request.response.statusCode = int.parse(request.uri.pathSegments.last);
        request.response.headers.set('content-type', 'text/html');
        request.response.write('<title>Not found</title>');
        await request.response.close();
      });
      await expectLater(site.fetch()('${site.base}/404'), refusedWith('The page answered 404.'));
      await expectLater(site.fetch()('${site.base}/500'), refusedWith('The page answered 500.'));
      await expectLater(site.fetch()('${site.base}/302'), refusedWith('The page answered 302.'), reason: 'a redirect to nowhere is its own answer');
    });

    test('gives up on a server that does not answer in time', () async {
      final never = Completer<void>();
      addTearDown(never.complete);
      final site = await Site.start((request) => never.future);
      final clock = Stopwatch()..start();
      await expectLater(site.fetch(timeout: const Duration(milliseconds: 150))(site.base), refusedWith(unreached));
      expect(clock.elapsed, lessThan(const Duration(seconds: 10)));
      expect(site.asked.length, 1);
    });

    test('keeps the time across redirects, and reads what had come when it ran out', () async {
      final never = Completer<void>();
      addTearDown(never.complete);
      final site = await Site.start((request) async {
        if (request.uri.path == '/slow-body') {
          request.response.bufferOutput = false;
          request.response.headers.set('content-type', 'text/html');
          request.response.write('<html><head><title>What came</title>');
          await request.response.flush();
          return never.future;
        }
        if (request.uri.path == '/stalls') return never.future;
        request.response.statusCode = 302;
        request.response.headers.set('location', '/stalls');
        await request.response.close();
      });
      await expectLater(site.fetch(timeout: const Duration(milliseconds: 300))('${site.base}/first'), refusedWith(unreached));
      expect(site.asked.map((request) => request.uri.path), <String>['/first', '/stalls']);
      expect((await site.fetch(timeout: const Duration(milliseconds: 300))('${site.base}/slow-body')).title, 'What came');
    });

    test('reads bytes that are not UTF-8 as UTF-8, whatever the page says it is written in', () async {
      final site = await Site.start((request) async {
        request.response.headers.set('content-type', request.uri.path == '/unknown' ? 'text/html; charset=klingon-8' : 'text/html; charset=iso-8859-1');
        request.response.add(<int>[...ascii.encode('<title>Caf'), 0xe9, ...ascii.encode(' ol'), 0xe9, ...ascii.encode('</title>'), ...utf8.encode('<meta name="description" content="naïve">')]);
        await request.response.close();
      });
      final preview = await site.fetch()('${site.base}/latin');
      expect(preview.title, 'Caf� ol�');
      expect(preview.description, 'naïve');
      expect((await site.fetch()('${site.base}/unknown')).title, 'Caf� ol�', reason: 'a charset nobody knows is no failure');
    });

    test('is a failure when nothing is listening, and when the address is not one', () async {
      final gone = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final port = gone.port;
      await gone.close(force: true);
      await expectLater(linkPreviewFetch(allow: (address, _) => address.isLoopback)('http://127.0.0.1:$port/'), refusedWith(unreached));
      await expectLater(linkPreviewFetch()('nonsense'), refusedWith("That isn't a web address."));
      await expectLater(linkPreviewFetch()('file:///etc/hosts'), refusedWith('Only web pages have previews.'));
    });

    // The Rust's `live::reads_a_real_page`, ignored there too. By hand: GHOST_LIVE=1 flutter test --no-pub
    // test/links/link_preview_fetch_test.dart --plain-name "reads a real page"
    test('reads a real page', () async {
      final preview = await linkPreviewFetch()('https://github.com/tauri-apps/tauri');
      printOnFailure('$preview');
      expect(preview.title, isNotNull);
    }, skip: Platform.environment['GHOST_LIVE'] == '1' ? false : 'reads a real site: run by hand');
  });
}
