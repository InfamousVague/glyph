/// A note's or a notebook's site, in its More sheet under Sharing (lib/share/sites.dart, docs/SITES.md): publish it as
/// a small website, copy its link, publish it again at the same address, or unpublish it.
///
/// Drawn under the shared link's rows by [ShareRows], so the bar's Share and the More sheet both have it. A journal is
/// shared an entry at a time and has no site; a build that does not offer sites (the iPhone's) has no [Sites] and draws
/// nothing at all. Signed out, the one line says where to sign in, as the link's does.
///
/// The words say what the person needs to know before pressing: anyone with the link can read the site, and nobody
/// else, the server included; no search engine can list it; and it changes only when they publish it again.
library;

import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../../account/ui_state.dart';
import '../../art/art.dart';
import '../../core/note.dart';
import '../../sheet/css.dart';
import '../../sheet/flow.dart';
import '../../sheet/kit.dart';
import '../../sync/engine.dart' show syncedWhen;
import '../share.dart';
import '../sites.dart';

/// The Site heading and its group, for [noteId]; [notebook] when it is a notebook's index.
class SiteRows extends StatefulWidget {
  const SiteRows({super.key, required this.services, required this.noteId, this.notebook = false, this.now});

  final AccountServices? services;
  final String noteId;
  final bool notebook;

  /// This moment, in ms: a test's clock.
  final int Function()? now;

  @override
  State<SiteRows> createState() => _SiteRowsState();
}

class _SiteRowsState extends State<SiteRows> {
  bool _busy = false;
  String? _said;

  Sites? get _sites => widget.services?.sites;

  @override
  void initState() {
    super.initState();
    _sites?.addListener(_changed);
    _read();
  }

  @override
  void didUpdateWidget(SiteRows old) {
    super.didUpdateWidget(old);
    if (old.services?.sites != _sites) {
      old.services?.sites?.removeListener(_changed);
      _sites?.addListener(_changed);
      _read();
    }
    if (old.noteId != widget.noteId) _said = null;
  }

  @override
  void dispose() {
    _sites?.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  /// The account's sites, read once a sheet first asks, so a site published on another device shows here.
  void _read() {
    final sites = _sites;
    if (sites == null || sites.read || !(widget.services?.signedIn ?? false)) return;
    unawaited(sites.refresh().then<void>((_) {}, onError: (Object _) {
      // Offline: the rows offer publishing, and a publish reads the list first.
    }));
  }

  Future<void> _run(Future<void> Function() work) async {
    setState(() {
      _busy = true;
      _said = null;
    });
    try {
      await work();
    } catch (failure) {
      if (mounted) setState(() => _said = accountFailureText(failure));
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _copy(String link, String said) async {
    try {
      await Clipboard.setData(ClipboardData(text: link));
      if (mounted) setState(() => _said = said);
    } catch (_) {
      if (mounted) setState(() => _said = link);
    }
  }

  Future<void> _publish() => _run(() async {
        final sites = _sites!;
        final notes = await sites.listNotes();
        Note? note;
        for (final each in notes) {
          if (each.id == widget.noteId) note = each;
        }
        if (note == null) throw const ShareError('Save the note first: there is nothing to publish yet.');
        final had = sites.siteFor(widget.noteId) != null;
        final site = await sites.publish(note, notes);
        if (had) {
          if (mounted) setState(() => _said = 'Published again, at the same address.');
        } else {
          await _copy(site.link, 'Published. The link is copied.');
        }
      });

  @override
  Widget build(BuildContext context) {
    final sites = _sites;
    if (sites == null) return const SizedBox.shrink();
    final t = context.tokens;
    final signedIn = widget.services?.signedIn ?? false;
    final site = signedIn ? sites.siteFor(widget.noteId) : null;
    final what = widget.notebook ? 'this notebook' : 'this note';
    final said = _said;
    const mark = AppIcon(Lucide.globe, size: 18, strokeWidth: 2.2);

    final List<Widget> rows;
    if (!signedIn) {
      rows = const [SheetRow(icon: mark, label: 'Publish as a site', hint: 'Sign in under Settings › Account first: a site is kept with your account.')];
    } else if (site == null) {
      rows = [
        SheetRow(
          key: const ValueKey('site-publish'),
          icon: mark,
          label: _busy ? 'Publishing…' : 'Publish as a site',
          hint: 'A small website of $what${widget.notebook ? ', its pages in order' : ''}. Anyone with the link can read it, and nobody else, the server included. Search engines can’t list it.',
          disabled: _busy,
          onPress: () => unawaited(_publish()),
        ),
      ];
    } else {
      final now = (widget.now ?? widget.services!.now)();
      rows = [
        SheetRow(
          key: const ValueKey('site-copy'),
          icon: const AppIcon(Lucide.copy, size: 18, strokeWidth: 2.2),
          label: 'Copy the site’s link',
          hint: 'Published ${syncedWhen(site.updated, now: now)}. Anyone with the link can read it.',
          onPress: () => unawaited(_copy(site.link, 'The link is copied.')),
        ),
        SheetRow(
          key: const ValueKey('site-again'),
          icon: const AppIcon(Lucide.refreshCw, size: 18, strokeWidth: 2.2),
          label: _busy ? 'Publishing…' : 'Publish again',
          hint: 'Puts your changes since on the site, at the same address.',
          disabled: _busy,
          onPress: () => unawaited(_publish()),
        ),
        SheetRow(
          key: const ValueKey('site-unpublish'),
          icon: const AppIcon(Lucide.x, size: 18, strokeWidth: 2.2),
          label: 'Unpublish',
          hint: 'The site goes, and its link reads nothing from then on.',
          disabled: _busy,
          onPress: () => unawaited(_run(() => sites.unpublish(site))),
        ),
      ];
    }

    return CssFlow(
      collapse: true,
      children: [
        const SheetHeading('Site'),
        SheetGroup(
          children: [
            ...rows,
            if (said != null)
              Padding(
                padding: EdgeInsets.symmetric(vertical: t.space(2), horizontal: t.space(4)),
                child: Semantics(liveRegion: true, child: Text(said, key: const ValueKey('site-said'), style: pageText(t, t.fontSize('sm'), color: t.color('glacier-text-subtle')))),
              ),
          ],
        ),
      ],
    );
  }
}
