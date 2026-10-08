import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../account/not_yet.dart';
import '../account/ui_state.dart';
import '../art/art.dart';
import '../orgs/join_links.dart';
import '../orgs/orgs.dart';
import '../orgs/ui/parts.dart';
import '../sheet/css.dart' show snapBorder;
import 'kit/settings_type.dart';

/// Port of `InviteLinks` (src/app/settings/InviteLinks.tsx, InviteLinks.module.css): invite by link, for the owner
/// and admins (docs/TEAMS.md; lib/orgs/join_links.dart). The organization's working links, each to copy, send or
/// turn off, and a new one made for a day, a week, thirty days or for good, for one person, a few, or anyone who
/// has it. Shown on the organization's Members page (organization_sheet.dart) and under its dashboard's invite
/// field (lib/orgs/ui/organization_screen.dart).
///
/// A link made is copied at once, since sending it is why it was made. The service's refusals are said under the
/// rows in its own words. Where the service has no invite links yet (`notYet`), nothing is drawn at all, the
/// heading [around] would have put over the panel included.
///
/// What differs from the web original:
/// - The calls are the [AccountServices]' organizations; with none there is nothing to read and nothing is drawn.
/// - **Send** is the platform's share sheet, which this app has no way to yet: the button is drawn only when
///   [onSend] is given, as the page draws it only where `navigator.share` exists.
/// - A device that will not copy cannot be told from one that will (the clipboard's call does not answer), so the
///   words that write the link out are said only when the call throws.
class InviteLinks extends StatefulWidget {
  const InviteLinks({super.key, required this.services, required this.orgId, this.inset = false, this.around, this.now, this.onSend});

  final AccountServices services;
  final String orgId;

  /// Inside a settings card, which pads its forms rather than its contents: padded as they are.
  final bool inset;

  /// The heading the panel sits under, drawn by the page around it and gone with it.
  final Widget Function(Widget panel)? around;

  /// This moment, in ms, for "Stops in 7 days"; the clock's when left out.
  final int Function()? now;

  /// Hands a link to the platform's share sheet (`navigator.share({ title, url })`).
  final void Function(String title, String url)? onSend;

  @override
  State<InviteLinks> createState() => _InviteLinksState();
}

class _InviteLinksState extends State<InviteLinks> {
  List<InviteLink>? _links;
  bool _missing = false;
  bool _making = false;
  String _lasts = 'week';
  String _uses = 'any';
  bool _busy = false;
  ({String words, bool problem})? _said;

  Orgs? get _orgs => widget.services.orgs;

  @override
  void initState() {
    super.initState();
    unawaited(_read());
  }

  @override
  void didUpdateWidget(InviteLinks old) {
    super.didUpdateWidget(old);
    if (old.orgId != widget.orgId) {
      _links = null;
      unawaited(_read());
    }
  }

  Future<void> _read() async {
    final orgs = _orgs;
    if (orgs == null) return setState(() => _missing = true);
    try {
      final links = await orgs.listInviteLinks(widget.orgId);
      if (mounted) setState(() => _links = links);
    } catch (failure) {
      if (!mounted) return;
      if (notYet(failure)) return setState(() => _missing = true);
      setState(() {
        _links = const [];
        _said = (words: accountFailureText(failure), problem: true);
      });
    }
  }

  Future<void> _copy(String code, [String words = 'The link is copied.']) async {
    try {
      await Clipboard.setData(ClipboardData(text: inviteUrl(code)));
      if (mounted) setState(() => _said = (words: words, problem: false));
    } catch (_) {
      // A device that will not copy: the link itself, to select and copy by hand.
      if (mounted) setState(() => _said = (words: 'This device wouldn’t copy it. The link: ${inviteUrl(code)}', problem: false));
    }
  }

  Future<void> _make() async {
    final orgs = _orgs;
    if (orgs == null) return;
    setState(() {
      _busy = true;
      _said = null;
    });
    try {
      final link = await orgs.makeInviteLink(
        widget.orgId,
        terms: LinkTerms(
          expiresIn: lifetimes.firstWhere((choice) => choice.value == _lasts, orElse: () => lifetimes.last).seconds,
          maxUses: uses.firstWhere((choice) => choice.value == _uses, orElse: () => uses.last).uses,
        ),
      );
      if (mounted) {
        setState(() {
          _links = [link, ...?_links];
          _making = false;
        });
      }
      await _copy(link.code, 'The link is made and copied. Anyone signed in who has it can join.');
    } catch (failure) {
      if (mounted) setState(() => _said = (words: accountFailureText(failure), problem: true));
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _turnOff(InviteLink link) async {
    final orgs = _orgs;
    if (orgs == null) return;
    setState(() => _said = null);
    try {
      await orgs.dropInviteLink(widget.orgId, link.id);
      if (!mounted) return;
      setState(() {
        _links = [for (final each in _links ?? const <InviteLink>[]) if (each.id != link.id) each];
        _said = (words: 'The link is turned off. No one else can join by it.', problem: false);
      });
    } catch (failure) {
      if (mounted) setState(() => _said = (words: accountFailureText(failure), problem: true));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_missing) return const SizedBox.shrink();
    final t = context.tokens;
    final sm = t.fontSize('sm'), xs = t.fontSize('xs');
    final quiet = pageText(t, sm, color: t.color('app-ink-2'));
    final links = _links;
    final said = _said;
    final now = (widget.now ?? widget.services.now)();
    final send = widget.onSend;

    Widget icon(LucideIcon mark, String label, VoidCallback onPressed) => GlacierPressable(
          onPressed: onPressed,
          semanticLabel: label,
          builder: (context, state) => GlacierFocusRing(
            visible: state.focused,
            radius: t.radius('full'),
            child: Container(
              width: t.lenOf('2.25rem'),
              height: t.lenOf('2.25rem'),
              decoration: BoxDecoration(shape: BoxShape.circle, color: state.hovered ? t.colorOf('color-mix(in oklch, var(--app-ink) 7%, transparent)') : null),
              alignment: Alignment.center,
              child: AppIcon(mark, size: 16, color: state.hovered ? t.color('app-ink') : t.color('app-ink-2')),
            ),
          ),
        );

    Widget choice(String label, String aria, List<GlacierSegmentedOption> options, String value, ValueChanged<String> onChange) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label, style: pageText(t, xs, color: t.color('app-ink-3'))),
            SizedBox(height: t.space(1)),
            GlacierSegmentedControl(ariaLabel: aria, fullWidth: true, size: GlacierSegmentedSize.sm, options: options, value: value, onValueChange: onChange),
          ],
        );

    final parts = <Widget>[
      if (links == null)
        Text('Reading the links…', style: quiet)
      else if (links.isNotEmpty)
        Semantics(
          label: 'Invite links',
          container: true,
          explicitChildNodes: true,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final link in links)
                Container(
                  key: ValueKey('invite-link:${link.id}'),
                  padding: EdgeInsets.symmetric(vertical: t.space(2)),
                  decoration: BoxDecoration(border: Border(bottom: BorderSide(color: t.color('app-rule'), width: snapBorder(context, t.len('glacier-hairline'))))),
                  child: Row(
                    children: [
                      ExcludeSemantics(child: AppIcon(Lucide.link2, size: 16, color: t.color('app-ink-3'))),
                      SizedBox(width: t.space(2)),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(linkName(link.code), style: pageText(t, sm, weight: 'medium', color: t.color('app-ink')), maxLines: 1, overflow: TextOverflow.ellipsis),
                            // `gap: 0.1em` of the page's text.
                            const SizedBox(height: 0.1 * 16),
                            Text(linkTermsWords(link, now), style: pageText(t, xs, color: t.color('app-ink-3')), maxLines: 1, overflow: TextOverflow.ellipsis),
                          ],
                        ),
                      ),
                      SizedBox(width: t.space(2)),
                      icon(Lucide.copy, 'Copy the link', () => unawaited(_copy(link.code))),
                      if (send != null) ...[
                        SizedBox(width: t.space(2)),
                        icon(Lucide.share2, 'Send the link', () => send('Join my team on Ghost.md', inviteUrl(link.code))),
                      ],
                      SizedBox(width: t.space(2)),
                      icon(Lucide.x, 'Turn the link off', () => unawaited(_turnOff(link))),
                    ],
                  ),
                ),
            ],
          ),
        )
      else
        Text('No links yet. Make one to send to people who should join.', style: quiet),
      if (_making)
        Padding(
          padding: EdgeInsets.symmetric(vertical: t.space(2)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              choice('Lasts', 'How long the link lasts', [for (final each in lifetimes) GlacierSegmentedOption(value: each.value, label: Text(each.label))], _lasts, (value) => setState(() => _lasts = value)),
              SizedBox(height: t.space(3)),
              choice('Who', 'How many can join by it', [for (final each in uses) GlacierSegmentedOption(value: each.value, label: Text(each.label))], _uses, (value) => setState(() => _uses = value)),
              SizedBox(height: t.space(3)),
              Wrap(
                spacing: t.space(2),
                runSpacing: t.space(2),
                children: [
                  OrgAction(label: _busy ? 'One moment…' : 'Make the link', primary: true, dim: 0.6, onPressed: _busy ? null : () => unawaited(_make())),
                  OrgAction(label: 'Cancel', dim: 0.6, onPressed: _busy ? null : () => setState(() => _making = false)),
                ],
              ),
            ],
          ),
        )
      else
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: OrgAction(
            key: const ValueKey('invite-link-new'),
            label: 'New link',
            icon: const AppIcon(Lucide.link2, size: 14),
            dim: 0.6,
            onPressed: () => setState(() {
              _said = null;
              _making = true;
            }),
          ),
        ),
      if (said != null) Semantics(liveRegion: true, child: Text(said.words, style: quiet)),
    ];

    final panel = Padding(
      padding: EdgeInsets.all(widget.inset ? t.space(3) : 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < parts.length; i++) ...[
            if (i > 0) SizedBox(height: t.space(2)),
            parts[i],
          ],
        ],
      ),
    );
    return widget.around?.call(panel) ?? panel;
  }
}
