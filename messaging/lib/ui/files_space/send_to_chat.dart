/// A file from My files sent into a chat (GMFB-37, @matt: "A private file drive for each account, not tied to any
/// space"; done looks like "Send a file from the drive into any chat").
///
/// It goes the way a file picked on this device goes into a space's chat (HangoutRoom.sendFiles): brought down from
/// the drive where it isn't here yet, then sealed again under the space's own seed and sent up into the space's own
/// storage, with a message that carries it. Nothing of the drive is shared: not its seed, its key or its list. A file
/// may be as big as the relay takes in the space it goes to (FilesInfo.maxFile).
///
/// Which chats: every space this device may write and send files in, its own and each circle's. Not a chat with a
/// friend by username, which carries words only for now (lib/ui/thread.dart refuses pictures and files there), nor a
/// conversation by text, whose pictures go as the phone's picture messages do. The sheet says so.
library;

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../../art/lucide.g.dart';
import '../../art/lucide_more.dart';
import '../../circles/circles.dart';
import '../../files/files_store.dart';
import '../../voice/channels.dart';
import '../../voice/hangout.dart';
import '../../voice/voice.dart';
import '../common.dart';
import '../space_chat_files.dart' show spaceMayAttach;

/// The spaces whose chat a file can be sent to from here: every space with a chat (not a group's call) that this
/// device's circle roles let it write and send files in; its own first, then each circle's by the circle's name.
List<VoiceChannel> chatsForFiles({Iterable<VoiceChannel>? from, Circles? circles}) {
  final cs = circles ?? Circles.instance;
  final spaces = [
    for (final c in from ?? Voice.instance.channels)
      if (c.hangout && cs.allows(c, CirclePerm.write) && cs.allows(c, CirclePerm.files)) c,
  ];
  String key(VoiceChannel c) => c.circle == null ? '' : '1${(cs.circleOf(c)?.name ?? '').toLowerCase()}\u0000${c.circle}';
  final order = {for (final (i, c) in spaces.indexed) c.seed: i};
  spaces.sort((a, b) {
    final k = key(a).compareTo(key(b));
    return k != 0 ? k : order[a.seed]!.compareTo(order[b.seed]!);
  });
  return spaces;
}

/// Sends the file at [path] into [room]'s chat, sealed up through [uploads]: null once the message has gone, else why
/// it didn't (it then waits in that chat with its Try again, where it got as far as being shown there).
Future<String?> sendPathToRoom(HangoutRoom room, String path, ChatUploads uploads, {Circles? circles}) async {
  final name = room.channel.name;
  if (!spaceMayAttach(room, circles: circles)) return room.putOut ?? 'Your role in $name can\'t send files.';
  final o = room.sendFiles([(path: path, owned: false)], uploads);
  if (o == null) return 'It couldn\'t be read to send.';
  final done = Completer<String?>();
  void watch() {
    if (done.isCompleted) return;
    if (!room.outgoing.contains(o)) {
      done.complete(null);
    } else if (o.failed) {
      done.complete('${o.error ?? o.files.first.error ?? 'It didn\'t go.'} It waits in $name\'s chat, with Try again.');
    }
  }

  room.addListener(watch);
  watch();
  try {
    return await done.future;
  } finally {
    room.removeListener(watch);
  }
}

/// Asks which chat [f] (a file of the drive [from]) goes to, then sends it there, saying how it went.
void sendFileToChat(BuildContext context, VoiceChannel from, SpaceFile f, {required FilesStore store, Iterable<VoiceChannel>? spaces}) {
  final toasts = GlacierToast.of(context);
  final to = chatsForFiles(from: spaces);
  if (to.isEmpty) {
    toast(context, 'There is no space to send it to yet. A file goes into a space\'s chat; chats with friends can\'t carry files yet.');
    return;
  }

  Future<void> send(VoiceChannel c) async {
    if (store.cached(f) == null) toasts.toast(message: Text('Getting ${f.name}…'));
    HangoutRoom? room;
    try {
      final path = await store.fetch(from, f);
      room = await Voice.instance.hold(c);
      if (room == null) {
        toasts.toast(message: const Text('Not connected to the relay yet. Try again in a moment.'), tone: GlacierToastTone.danger);
        return;
      }
      toasts.toast(message: Text('Sending ${f.name} to ${c.name}'));
      final why = await sendPathToRoom(room, path, store);
      toasts.toast(message: Text(why ?? '${f.name} sent to ${c.name}'), tone: why == null ? GlacierToastTone.success : GlacierToastTone.danger);
    } on FilesError catch (e) {
      // -1: stopped by the person as it came down.
      if (e.status != -1) toasts.toast(message: Text(e.message), tone: GlacierToastTone.danger);
    } catch (e) {
      toasts.toast(message: Text('Couldn\'t send it: $e'), tone: GlacierToastTone.danger);
    } finally {
      // The room was held only for the sending.
      if (room != null) unawaited(Voice.instance.release(c));
    }
  }

  showChoices(
    context,
    title: 'Send ${f.name} to\nIt goes into a space\'s chat. Chats with friends can\'t carry files yet.',
    choices: [
      for (final c in to)
        Choice(c.name, c.kind == SpaceKind.files ? Lucide.folder : LucideMore.messageCircle, () => unawaited(send(c)), hint: Circles.instance.circleOf(c)?.name),
    ],
  );
}
