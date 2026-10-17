/// Remind me at a place: the sheet press and hold opens for a to-do, and a place chip's Change place
/// (docs/INTEGRATIONS.md §3). Three ways to a place, top to bottom:
///
/// - **Search**: a place by its name, asked of OpenStreetMap's Nominatim when the search is sent (never as the words
///   are typed, which its usage policy forbids), as the app (lib/core/geocode.dart `geocodeSearch`). Not offered under
///   Local only, which sends nothing anywhere: the sheet says so.
/// - **In this note**: the places the note already has, its place lines and the other to-dos' `📍`, each once.
/// - **Here**: where the phone is now, with its name where one may be asked (lib/core/location.dart), or the
///   coordinates. Not offered where this device cannot say where it is, or Local only is on.
///
/// The place picked is handed back ([PlaceSheet.onDone]) and written by whoever opened the sheet
/// (lib/editor/items/field_menu.dart `pickLinePlace`); put away, nothing is.
library;

import 'dart:async';

import 'package:flutter/services.dart' show TextCapitalization, TextInputAction;
import 'package:flutter/widgets.dart';

import '../art/app_icon.dart';
import '../art/lucide.g.dart';
import '../core/geocode.dart' show GeocodeError, PlaceHit, PlaceSearch;
import '../core/place_refs.dart' show placeLines;
import '../sheet/kit.dart';
import '../sheet/sheet.dart';
import 'place_syntax.dart';

/// The places [body] already has, each once, in the order it has them: its place lines and its to-dos' `📍`.
List<PlaceMark> placesInNote(String body) {
  final out = <PlaceMark>[];
  final seen = <String>{};
  void add(PlaceMark mark) {
    if (seen.add(mark.link)) out.add(mark);
  }

  final lines = placeLines(body);
  final numbered = {for (final place in lines) place.line: place};
  final all = body.split('\n');
  var fenced = false;
  for (var index = 0; index < all.length; index += 1) {
    final text = all[index];
    if (text.trimLeft().startsWith('```') || text.trimLeft().startsWith('~~~')) {
      fenced = !fenced;
      continue;
    }
    if (fenced) continue;
    final line = numbered[index + 1];
    if (line != null) {
      add(PlaceMark(line.tag));
      continue;
    }
    final mark = placeOn(text);
    if (mark != null) add(mark);
  }
  return out;
}

/// What the app says before Android's "Allow all the time" (place_access.dart): why, and what to choose. Continue
/// raises Android's own; Not now leaves the reminder written, and its chip warns.
class PlaceAllowSheet extends StatelessWidget {
  const PlaceAllowSheet({super.key, required this.onDone, this.place});

  /// The place just picked, said by name.
  final String? place;

  /// True for Continue, false where it was put away.
  final ValueChanged<bool> onDone;

  @override
  Widget build(BuildContext context) {
    final there = place == null || place!.isEmpty ? 'a place on one of your to-dos' : place!;
    return Sheet(
      label: 'Location all the time',
      onClose: () => onDone(false),
      children: [
        SheetTitle.text('Remind you when you arrive'),
        SheetNote(
          'To remind you when you get to $there, Ghost.md needs to know where your phone is while the app is closed. Android asks next: choose “Allow all the time”. Ghost.md only uses it to notice when you reach a place written on a to-do, and never sends where you are anywhere.',
        ),
        SheetGroup(
          children: [
            SheetRow(icon: const AppIcon(Lucide.mapPin, size: 18), label: 'Continue', onPress: () => onDone(true)),
            SheetRow(label: 'Not now', hint: 'The reminder is kept, but it won’t ring until you allow it.', onPress: () => onDone(false)),
          ],
        ),
      ],
    );
  }
}

/// Where the phone is now, as a place: its name where one came. Throws where it could not say.
typedef HerePlace = Future<PlaceMark> Function();

class PlaceSheet extends StatefulWidget {
  const PlaceSheet({super.key, required this.body, required this.onDone, this.current, this.search, this.here, this.hereWhy, this.localOnly = false});

  /// The note's words, for the places it already has.
  final String body;

  /// The place the line has now, lit among the note's.
  final PlaceMark? current;

  /// A place by its name; null where none may be asked (Local only, or no network in this build).
  final PlaceSearch? search;

  /// Where the phone is now; null where it cannot say ([hereWhy] says why, where it can be said).
  final HerePlace? here;
  final String? hereWhy;

  /// Local only is on: the search is not offered, and the sheet says why.
  final bool localOnly;

  /// The place picked, or null where the sheet was put away.
  final ValueChanged<PlaceMark?> onDone;

  @override
  State<PlaceSheet> createState() => _PlaceSheetState();
}

class _PlaceSheetState extends State<PlaceSheet> {
  String _query = '';
  bool _searching = false;
  bool _locating = false;
  List<PlaceHit>? _hits;
  String? _problem;
  String? _hereProblem;
  bool _done = false;

  late final List<PlaceMark> _inNote = placesInNote(widget.body);

  void _finish(PlaceMark? mark) {
    if (_done) return;
    _done = true;
    widget.onDone(mark);
  }

  Future<void> _search() async {
    final search = widget.search;
    final query = _query.trim();
    if (search == null || query.isEmpty || _searching) return;
    setState(() {
      _searching = true;
      _problem = null;
    });
    try {
      final hits = await search(query);
      if (!mounted) return;
      setState(() {
        _hits = hits;
        _problem = hits.isEmpty ? 'Nothing was found for “$query”.' : null;
      });
    } catch (failure) {
      if (!mounted) return;
      setState(() => _problem = failure is GeocodeError ? failure.message : 'The search didn’t work. Try again.');
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  Future<void> _here() async {
    final here = widget.here;
    if (here == null || _locating) return;
    setState(() {
      _locating = true;
      _hereProblem = null;
    });
    try {
      final mark = await here();
      if (!mounted) return;
      _finish(mark);
    } catch (_) {
      if (mounted) setState(() => _hereProblem = 'Ghost.md couldn’t find where you are just now.');
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final hits = _hits;
    final current = widget.current;
    return Sheet(
      label: 'Remind me at a place',
      onClose: () => _finish(null),
      children: [
        SheetTitle.text('Remind me at a place'),
        const SheetNote('When your phone arrives there, this to-do reminds you. Tick it and the reminder goes.'),
        if (widget.search != null)
          SheetGroup(
            children: [
              SheetField(
                label: 'Search for a place',
                value: _query,
                placeholder: 'A shop, a street, a town',
                onChange: (text) => setState(() => _query = text),
                autoCapitalize: TextCapitalization.words,
                maxLength: 200,
                enterKeyHint: TextInputAction.search,
                onSubmitted: (_) => unawaited(_search()),
              ),
              SheetRow(
                icon: const AppIcon(Lucide.search, size: 18),
                label: _searching ? 'Searching…' : 'Search',
                hint: _problem,
                disabled: _searching || _query.trim().isEmpty,
                onPress: () => unawaited(_search()),
              ),
              if (hits != null)
                for (final hit in hits)
                  SheetRow(
                    icon: const AppIcon(Lucide.mapPin, size: 18),
                    label: hit.name,
                    hint: hit.address == hit.name ? null : hit.address,
                    onPress: () => _finish(PlaceMark.at(hit.lat, hit.lon, name: hit.name)),
                  ),
            ],
          )
        else if (widget.localOnly)
          const SheetNote('Searching for a place is off while Local only is on, since it asks OpenStreetMap. A place already in this note still works.'),
        if (_inNote.isNotEmpty) ...[
          const SheetHeading('In this note'),
          SheetGroup(
            children: [
              for (final mark in _inNote)
                SheetRow(icon: const AppIcon(Lucide.mapPinned, size: 18), label: mark.name, chosen: current == null ? null : current == mark, onPress: () => _finish(mark)),
            ],
          ),
        ],
        SheetGroup(
          children: [
            SheetRow(
              icon: const AppIcon(Lucide.locateFixed, size: 18),
              label: _locating ? 'Finding where you are…' : 'Here',
              hint: widget.here == null ? (widget.hereWhy ?? 'This device can’t say where it is.') : (_hereProblem ?? 'Where you are now'),
              disabled: widget.here == null || _locating,
              onPress: widget.here == null ? null : () => unawaited(_here()),
            ),
            SheetRow(label: 'Cancel', onPress: () => _finish(null)),
          ],
        ),
      ],
    );
  }
}
