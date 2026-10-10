import 'package:flutter/widgets.dart';
import 'package:ghost_md/root/selected.dart';

/// What a part of the root draws (lib/root/selected.dart): the widget its builder makes now, for a test that reads
/// what the root hands a screen (a press, an art) without putting the screen up. The shell's builders answer the
/// part, which builds the screen only when what it reads has changed.
T partOf<T extends Widget>(BuildContext context, Widget part) {
  if (part is! Selected) return part as T;
  final dynamic selected = part;
  // ignore: avoid_dynamic_calls
  return selected.builder(context, selected.select()) as T;
}
