import 'dart:convert';

import 'package:ghost_md/core/phone_notices.dart';

/// The phone, as a test stands in for it: what it was handed, and what it says.
class FakePhone implements NoticesHost {
  final List<Map<String, Object?>> posted = [];
  final List<String> watches = [];
  NoticesState current = NoticesState.on;

  /// Whether the binary has notices at all; without, every call answers nothing.
  bool there = true;

  @override
  Future<bool> post(PhoneNotice notice) async {
    if (!there) return false;
    posted.add((jsonDecode(noticeJson(notice)) as Map).cast<String, Object?>());
    return true;
  }

  @override
  Future<NoticesState?> watch(String json) async {
    if (!there) return null;
    watches.add(json);
    return current = json.isEmpty ? NoticesState.off : NoticesState.on;
  }

  /// How many times it was asked what it says now.
  int asked = 0;

  @override
  Future<NoticesState?> state() async {
    asked += 1;
    return there ? current : null;
  }

  /// How many times it was asked to let the app notify, and what it answers: whether a prompt could change it.
  int allows = 0;
  bool prompts = true;

  @override
  Future<bool> allow() async {
    if (!there) return false;
    allows += 1;
    return prompts;
  }
}
