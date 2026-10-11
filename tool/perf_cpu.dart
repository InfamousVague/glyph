// The CPU's side of a measured walk (lib/perf/perf_run.dart): which Dart functions the UI thread spent each
// stretch in. Run beside a PROFILE build that is taking its walk; it reads the VM's own samples while the walk
// goes (the VM keeps only so many), keeps them beside the report, cuts them by the stretches the app reports,
// prints the hottest functions of each, and tells the app it may go.
//
//   dart run tool/perf_cpu.dart <the walk's folder> [--top 30] [--only home-fling-down,note-type]
//   dart run tool/perf_cpu.dart <the walk's folder> --saved [...]      the samples of the last walk, read again
//
// The folder is `<cache>/perf` of the app (tool/perf.sh says where). A function's "in" is the share of the
// stretch's samples with it anywhere on the stack (it or what it called); "self" is the share with it on top.
// The app's own functions and the kit's are listed apart from the framework's, since those are the ones to change.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:vm_service/vm_service.dart';
import 'package:vm_service/vm_service_io.dart';

class _Sample {
  _Sample(this.at, this.stack);
  final int at;

  /// The functions on the stack, innermost first, each by its number in [_names].
  final List<int> stack;
}

final List<String> _names = [];
final Map<String, int> _numbers = {};
int _numberOf(String name) => _numbers[name] ??= () {
      _names.add(name);
      return _names.length - 1;
    }();

// The checkout's folder is `glyph` (or `glyph-…`) since this app became that repository's root (docs/CUTOVER.md §5),
// and was `ghost-flutter` before; never the Tauri app's own tree below it, which has no lib/.
final RegExp _ownLib = RegExp(r'/(?:ghost-flutter|glyph)[^/]*/lib/');

String _where(String url) {
  // The tree's own files, in the main checkout or in a worktree beside it (ghost-flutter-paint and the like).
  final lib = _ownLib.firstMatch(url);
  if (lib != null) return 'app:${url.substring(lib.end)}';
  final kit = url.indexOf('/packages/glacier/lib/src/');
  if (kit >= 0) return 'kit:${url.substring(kit + '/packages/glacier/lib/src/'.length)}';
  final flutter = url.indexOf('/packages/flutter/lib/src/');
  if (flutter >= 0) return 'flutter:${url.substring(flutter + '/packages/flutter/lib/src/'.length)}';
  final sdk = url.indexOf('/sdk/lib/');
  if (sdk >= 0) return 'dart:${url.substring(sdk + '/sdk/lib/'.length)}';
  final ui = url.indexOf('/flutter/lib/ui/');
  if (ui >= 0) return 'ui:${url.substring(ui + '/flutter/lib/ui/'.length)}';
  return url.replaceFirst('package:ghost_md/', 'app:').replaceFirst('package:glacier/src/', 'kit:').replaceFirst('package:flutter/src/', 'flutter:');
}

String _nameOf(ProfileFunction profiled) {
  final function = profiled.function;
  var name = '?';
  if (function is FuncRef) {
    name = function.name ?? '?';
    Object? owner = function.owner;
    // A closure's owner is the function it was written in; a method's is its class.
    for (var depth = 0; depth < 6 && owner != null; depth += 1) {
      if (owner is ClassRef) {
        name = '${owner.name}.$name';
        break;
      }
      if (owner is FuncRef) {
        name = '${owner.name}.$name';
        owner = owner.owner;
        continue;
      }
      break;
    }
  } else if (function is NativeFunction) {
    name = '[native] ${function.name}';
  }
  final where = _where(profiled.resolvedUrl ?? '');
  return where.isEmpty ? name : '$name  ($where)';
}

/// Which part of the code a function is in, for the stretch's sum by part.
String _partOf(String named) {
  final open = named.lastIndexOf('  (');
  if (open < 0) return named.startsWith('[native]') ? 'native' : 'vm';
  final where = named.substring(open + 3, named.length - 1);
  final colon = where.indexOf(':');
  if (colon < 0) return where;
  final kind = where.substring(0, colon), rest = where.substring(colon + 1).split('/');
  if (kind == 'app') return 'app:${rest.first}${rest.length > 2 ? '/${rest[1]}' : ''}';
  return '$kind:${rest.first}';
}

bool _ours(String named) => named.contains('  (app:') || named.contains('  (kit:');

Future<List<_Sample>> _collect(Directory dir, File reportFile) async {
  final vmFile = File('${dir.path}/vm.txt');
  stderr.writeln('waiting for the app to say where its VM is (${vmFile.path})');
  for (var waited = 0; !vmFile.existsSync(); waited += 1) {
    if (waited > 1200) {
      stderr.writeln('the app never said');
      exit(1);
    }
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
  final http = Uri.parse(vmFile.readAsStringSync().trim());
  final ws = http.replace(scheme: 'ws', path: '${http.path.endsWith('/') ? http.path : '${http.path}/'}ws');
  final service = await vmServiceConnectUri(ws.toString());
  final vm = await service.getVM();
  final isolate = vm.isolates!.firstWhere((each) => each.name == 'main', orElse: () => vm.isolates!.first);
  // A build started by hand has its profiler off until something asks for it.
  try {
    await service.setFlag('profile_period', '500');
    await service.setFlag('profiler', 'true');
  } catch (failure) {
    stderr.writeln('the profiler would not be turned on: $failure');
  }
  stderr.writeln('reading the samples of ${isolate.name} at $ws');

  final samples = <_Sample>[];
  var from = (await service.getVMTimelineMicros()).timestamp!;
  Future<void> read() async {
    final int now;
    final CpuSamples got;
    try {
      now = (await service.getVMTimelineMicros()).timestamp!;
      got = await service.getCpuSamples(isolate.id!, from, now - from);
    } catch (failure) {
      stderr.writeln('a read failed: $failure');
      return;
    }
    final numbers = [for (final function in got.functions ?? const <ProfileFunction>[]) _numberOf(_nameOf(function))];
    for (final sample in got.samples ?? const <CpuSample>[]) {
      final at = sample.timestamp;
      if (at == null || at < from) continue;
      samples.add(_Sample(at, [for (final index in sample.stack ?? const <int>[]) numbers[index]]));
    }
    from = now;
  }

  // The app says when to read: between two stretches of its walk, where the stop a read is (the VM writes the
  // samples out on the app's own UI isolate) is measured as neither. A build from before it said so, or a stretch
  // longer than the VM keeps samples for, is read anyway after a while.
  final ask = File('${dir.path}/read');
  var quiet = 0;
  while (!reportFile.existsSync()) {
    await Future<void>.delayed(const Duration(milliseconds: 50));
    quiet += 50;
    if (ask.existsSync() || quiet >= 25000) {
      await read();
      quiet = 0;
      try {
        if (ask.existsSync()) ask.deleteSync();
      } catch (_) {}
    }
  }
  await read();
  File('${dir.path}/samples.json').writeAsStringSync(jsonEncode({
    'names': _names,
    'samples': [
      for (final sample in samples) [sample.at, sample.stack],
    ],
  }));
  File('${dir.path}/done').writeAsStringSync('read\n');
  await service.dispose();
  return samples;
}

List<_Sample> _saved(Directory dir) {
  final kept = jsonDecode(File('${dir.path}/samples.json').readAsStringSync()) as Map<String, Object?>;
  for (final name in (kept['names']! as List).cast<String>()) {
    _numberOf(name);
  }
  return [
    for (final each in (kept['samples']! as List).cast<List<Object?>>()) _Sample(each[0]! as int, (each[1]! as List).cast<int>()),
  ];
}

Future<void> main(List<String> args) async {
  if (args.isEmpty) {
    stderr.writeln('usage: dart run tool/perf_cpu.dart <the walk\'s folder> [--saved] [--top 30] [--only a,b]');
    exit(64);
  }
  final dir = Directory(args.first);
  var top = 30;
  Set<String>? only;
  for (var i = 1; i < args.length - 1; i += 1) {
    if (args[i] == '--top') top = int.parse(args[i + 1]);
    if (args[i] == '--only') only = args[i + 1].split(',').toSet();
  }
  final reportFile = File('${dir.path}/report.json');
  final samples = args.contains('--saved') ? _saved(dir) : await _collect(dir, reportFile);
  final report = jsonDecode(reportFile.readAsStringSync()) as Map<String, Object?>;
  final stretches = (report['stretches']! as List).cast<Map<String, Object?>>();
  stdout.writeln('${samples.length} samples over ${stretches.length} stretches, ${report['mode']} build, window ${report['window']}, launch ${report['launch']}');
  for (final stretch in stretches) {
    final name = stretch['name']! as String;
    if (only != null && !only.contains(name)) continue;
    final began = stretch['began']! as int, ended = stretch['ended']! as int;
    final here = [
      for (final sample in samples)
        if (sample.at >= began && sample.at < ended && sample.stack.isNotEmpty) sample,
    ];
    stdout.writeln('\n== $name: ${stretch['ms']} ms, ${stretch['frames']} frames, build ${stretch['build']}, raster ${stretch['raster']}, '
        '${stretch['slow']} slow, ${stretch['dropped']} dropped; ${here.length} samples${stretch['counts'] == null ? '' : '; ${stretch['counts']}'}');
    if (here.isEmpty) continue;
    final inside = <int, int>{}, self = <int, int>{}, parts = <String, int>{};
    for (final sample in here) {
      final leaf = sample.stack.first;
      self[leaf] = (self[leaf] ?? 0) + 1;
      final part = _partOf(_names[leaf]);
      parts[part] = (parts[part] ?? 0) + 1;
      for (final each in sample.stack.toSet()) {
        inside[each] = (inside[each] ?? 0) + 1;
      }
    }
    String share(int count) => '${(100 * count / here.length).toStringAsFixed(1).padLeft(5)}%';
    final byPart = parts.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    stdout.writeln('   self by part: ${[for (final part in byPart.take(16)) '${part.key} ${share(part.value).trim()}'].join(', ')}');
    final byInside = inside.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    stdout.writeln('   -- the app\'s and the kit\'s own, by time in them:   in     self   function');
    for (final entry in byInside.where((entry) => _ours(_names[entry.key])).take(top)) {
      stdout.writeln('   ${share(entry.value)} ${share(self[entry.key] ?? 0)}  ${_names[entry.key]}');
    }
    final bySelf = self.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    stdout.writeln('   -- anything, by time on top');
    for (final entry in bySelf.take(top ~/ 2)) {
      stdout.writeln('   ${share(inside[entry.key] ?? 0)} ${share(entry.value)}  ${_names[entry.key]}');
    }
  }
  exit(0);
}
