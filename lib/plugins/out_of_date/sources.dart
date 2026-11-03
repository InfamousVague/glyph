/// The app's sources of the one "May be out of date" mark (out_of_date.dart; Matt, 2026-11-02: "Yes, fold them"): the
/// Contradiction finder's, then Note decay alerts', so on a line both flag the newer note's words come first. And what
/// says they may answer otherwise: the decay's own news, and the registry, which the finder's root part tells when its
/// findings change (lib/root/root_contradictions.dart `offersChanged`) and which hears either plugin switched.
library;

import 'package:flutter/foundation.dart';

import '../contradictions/contradictions.dart' show contradictionRunner, contradictionsOutOfDate;
import '../note_decay/decay.dart' show noteDecay;
import '../note_decay/source.dart' show decayOutOfDate;
import '../registry.dart' show plugins;
import 'out_of_date.dart';

final OutOfDateSource _decay = decayOutOfDate();

/// The sources, in the order their reasons are listed.
List<OutOfDateSource> appOutOfDateSources() => [contradictionsOutOfDate, _decay];

/// What the open note's marks listen to, as the app has them now.
Listenable appOutOfDateChanges() => Listenable.merge([?noteDecay, plugins, contradictionRunner]);
