/// Files shared into the app from another (Android's share sheet): added to a Files space the person picks (Matt,
/// 2026-11-17: "add full functionality for filesharing in a space when the space is designated a Files Space").
library;

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../../art/lucide.g.dart';
import '../../files/file_platform.dart';
import '../../files/files_store.dart';
import '../../voice/channels.dart';
import '../../voice/voice.dart';
import '../common.dart';
import 'files_screen.dart';

class FilesShareIn {
  FilesShareIn._();
  static StreamSubscription<List<String>>? _sub;

  /// Listens for files shared in, asking on [navigator]'s page which Files space each lot goes to.
  static void attach(GlobalKey<NavigatorState> navigator) {
    _sub ??= FilePlatform.sharedIn().listen((uris) {
      if (uris.isEmpty) return;
      // The app's first frame may not be up yet when it was opened by the share.
      WidgetsBinding.instance.addPostFrameCallback((_) => _ask(navigator, uris));
    });
  }

  static void _ask(GlobalKey<NavigatorState> navigator, List<String> uris) {
    final context = navigator.currentContext;
    if (context == null) return;
    final spaces = [for (final c in Voice.instance.channels) if (c.kind == SpaceKind.files && FilesStore.instance.canUpload(c)) c];
    final what = uris.length == 1 ? 'this file' : 'these ${uris.length} files';
    if (spaces.isEmpty) {
      showChoices(context, title: 'There is no Files space to add $what to yet. Make one in a circle, or as a space of its own, then share again.', choices: [
        Choice('OK', Lucide.check, () {}),
      ]);
      return;
    }
    showChoices(context, title: 'Add $what to', choices: [
      for (final c in spaces)
        Choice(c.name, Lucide.folder, () => unawaited(_add(navigator, c, uris)), hint: c.circle == null ? 'Files space' : 'Files space in a circle'),
    ]);
  }

  static Future<void> _add(GlobalKey<NavigatorState> navigator, VoiceChannel c, List<String> uris) async {
    final paths = <String>[];
    for (final u in uris) {
      final p = await FilePlatform.keep(u);
      if (p != null) paths.add(p);
    }
    final context = navigator.currentContext;
    if (paths.isEmpty) {
      if (context != null && context.mounted) toast(context, 'Those files couldn\'t be read.', tone: GlacierToastTone.danger);
      return;
    }
    FilesStore.instance.upload(c, paths, owned: true);
    if (context == null || !context.mounted) return;
    toast(context, 'Adding ${paths.length == 1 ? '1 file' : '${paths.length} files'} to ${c.name}');
    push<void>(context, (_) => FilesSpaceScreen(channel: c));
  }
}
