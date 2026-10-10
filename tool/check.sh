#!/bin/sh
# The whole suite, one thing at a time, in the order that fails soonest: the kit, the app folder by folder, the
# analyzer, the two folders that want the real service (tool/local-server.sh), and the Rust core's own tests.
#
#   tool/check.sh                     everything
#   tool/check.sh --since <rev>       the quick one: the kit and the folders of test/ that what changed since <rev>
#                                     can reach (committed since, not committed yet, or not yet known to git), and
#                                     the analyzer. --quick is --since HEAD: what is not committed yet.
#   tool/check.sh --since <rev> --list    says what that would run, and the changed file that reaches each; runs nothing
#
#   tool/check.sh kit                 packages/glacier
#   tool/check.sh app                 every folder of test/ (and the tests at its top), each in a run of its own
#   tool/check.sh app root editor     those folders only
#   tool/check.sh test <arguments>    one `flutter test` of whatever is named, with the same limits and the same
#                                     report: a file, --plain-name '<a test>', --update-goldens
#   tool/check.sh analyze             lib/, test/ and packages/glacier: no error and no warning
#   tool/check.sh server              test/e2e and test/live against the service on this Mac, started and stopped here
#   tool/check.sh native              tool/build-native.sh test (cargo's tests; long, and it takes the build lock)
#   tool/check.sh pictures            what a run left changed among the pictures (it says; it changes nothing)
#
# It stops at nothing: every part runs, each failing test is named with the first line of why, and the exit is 1 if
# anything failed. Each run's report is kept in build/check/<name>.json (flutter's own, an event a line) with its
# log beside it.
#
# WHAT --since REACHES. A test is reached by a changed file if it, or anything it imports, imports that file or
# names it in a string (`File('android/app/src/main/AndroidManifest.xml')`, a folder of fixtures, `Directory('lib')`:
# test/diag reads every file of lib/, so every change there reaches it). Besides that: a picture or a fixture under
# test/<folder>/ reaches its folder; pubspec.yaml, assets/ and shaders/ reach everything, since every screen is
# drawn with them; native/ reaches the tests that open the Mac's build of the core. It does NOT run `server` or
# `native`, and says so where what changed asks for them. What changed in ../glyph is not seen at all.
# GHOST_CHECK_FILES="lib/a.dart lib/b.dart" tool/check.sh --since HEAD --list answers for those files instead:
# what a change there would have to be checked by.
#
# Other sessions share this Mac, so:
#   - every `flutter test` is --concurrency=2, and one check runs at a time: a second one waits for the first
#     (/tmp/ghost-flutter-check.lock, which holds the first one's process id and is taken over if that is gone);
#   - before each run it waits while the one-minute load is GHOST_CHECK_LOAD (40) or more: a picture's settle, a
#     keystroke's budget and a derivation at the real rounds are each measured in this Mac's time;
#   - cargo is given GHOST_JOBS (4) jobs, and every cargo build is made under the lock every build takes here
#     (/tmp/ghost-flutter-build.lock, a directory made and removed).
#
# A folder is one that git knows a test in: a probe left untracked in a folder of its own under test/ is not run.
#
# PICTURES. A picture test compares with its reference and writes nothing (what differed is left in a git-ignored
# `failures/` beside it: the reference, the new picture, the difference). A few under test/art draw their
# reference again on every run; `pictures`, at the end of everything, says which files those were. A reference is
# drawn again only after it has been looked at beside the new one, and BY ITS WHOLE FILE, never by one test's name:
#   tool/check.sh test --update-goldens test/<folder>/<file>_test.dart     then `git status`: only the stale ones moved
# A picture depends on the tests before it in its file. The smoke's programs (lib/art/wisp_kit.dart) are loaded
# once for a whole file, off the first frame, and a test's clock never lets that end before its first picture is
# taken: the first picture of a file is drawn with no smoke and the later ones with it, and the references were
# drawn that way (test/root/root_test.dart's "home, fold, dark" is 49,378 pixels from its reference run alone,
# --plain-name, and right in its file). Until a test says what the kit holds before it draws, one test run alone
# may fail on its picture and mean nothing by it.
set -u

root="$(cd "$(dirname "$0")/.." && pwd)"
out="$root/build/check"
most="${GHOST_CHECK_LOAD:-40}"
jobs="${GHOST_JOBS:-4}"
build_lock=/tmp/ghost-flutter-build.lock
check_lock=/tmp/ghost-flutter-check.lock
library="$root/native/target/debug/libghost_core.dylib"
failed=""
passed=0
failures=0
skipped=0
held=""
building=""
serving=""
mkdir -p "$out"
cd "$root"

say() { echo "check: $*"; }

# One check at a time on this Mac. The lock is a directory holding the process that made it.
take_turn() {
  [ -n "$held" ] && return 0
  while ! mkdir "$check_lock" 2>/dev/null; do
    other="$(cat "$check_lock/pid" 2>/dev/null || true)"
    if [ -n "$other" ] && ! kill -0 "$other" 2>/dev/null; then
      # Whoever held it is gone (a restart, a session ended): it is taken over.
      rm -rf "$check_lock"
      continue
    fi
    say "another check is running (process ${other:-?}); waiting for it..."
    sleep 15
  done
  echo $$ >"$check_lock/pid"
  held=1
  trap 'leave' EXIT
  trap 'leave; exit 130' INT TERM
}

# Whatever this run holds is let go, however it ends: its turn, the build lock, the service it started.
leave() {
  [ -z "$serving" ] || tool/local-server.sh stop >/dev/null 2>&1
  [ -z "$building" ] || rmdir "$build_lock" 2>/dev/null
  [ -z "$held" ] || rm -rf "$check_lock"
  serving=""; building=""; held=""
}

# Every build on this Mac is made one at a time.
build_turn() {
  until mkdir "$build_lock" 2>/dev/null; do sleep 10; done
  building=1
}

built() {
  rmdir "$build_lock" 2>/dev/null
  building=""
}

quiet() {
  # macOS and Linux both: the first number of the load average.
  while :; do
    load="$( (sysctl -n vm.loadavg 2>/dev/null || cat /proc/loadavg) | tr -d '{}' | awk '{print int($1)}')"
    [ "${load:-0}" -lt "$most" ] && return 0
    say "the load is $load; waiting for under $most..."
    sleep 20
  done
}

# What a run's report says: its counts on the first line, then each failing test with the first line of why, then
# why whatever was skipped was.
report() {
  python3 - "$1" "$root" <<'EOF'
import json, sys
tests, suites, said, errors = {}, {}, {}, {}
ok = bad = skipped = 0
names, why = [], {}
try:
    rows = open(sys.argv[1], encoding='utf-8', errors='replace').read().splitlines()
except OSError:
    rows = []
for row in rows:
    try:
        e = json.loads(row)
    except ValueError:
        continue
    t = e.get('type')
    if t == 'suite':
        suites[e['suite']['id']] = e['suite']['path']
    elif t == 'testStart':
        tests[e['test']['id']] = e['test']
    elif t == 'print':
        said.setdefault(e.get('testID'), []).extend(str(e.get('message', '')).splitlines())
    elif t == 'error':
        errors.setdefault(e.get('testID'), []).extend(str(e.get('error', '')).splitlines())
    elif t == 'testDone':
        test = tests.get(e['testID'], {})
        if e['result'] != 'success':
            names.append(e['testID'])
        if e.get('hidden'):
            continue
        if e.get('skipped'):
            skipped += 1
            reason = (test.get('metadata') or {}).get('skipReason') or 'no reason given'
            why[reason] = why.get(reason, 0) + 1
        elif e['result'] != 'success':
            bad += 1
        else:
            ok += 1


def first(test):
    # A widget test's failure is printed by the framework, under "The following ... was thrown"; a plain test's
    # and a file that did not compile say it in the error itself.
    lines = [line.strip() for line in said.get(test, []) if line.strip()]
    for at, line in enumerate(lines):
        if line.startswith('The following') and at + 1 < len(lines):
            more = lines[at + 2] if at + 2 < len(lines) and lines[at + 1].startswith('Expected:') else ''
            return (lines[at + 1] + ('  ' + more if more else ''))[:230]
    lines = [line.strip() for line in errors.get(test, []) if line.strip()]
    for line in lines:
        if 'Error: ' in line:
            return line[:230]
    return ' '.join(lines[:2])[:230]


print('%d passed, %d failed, %d skipped' % (ok, bad, skipped))
for test in names:
    path = str(suites.get(tests.get(test, {}).get('suiteID'), '?')).replace(sys.argv[2] + '/', '')
    print('  FAILED %s :: %s' % (path, tests.get(test, {}).get('name')))
    reason = first(test)
    if reason:
        print('         %s' % reason)
for reason, count in sorted(why.items()):
    print('  skipped %d: %s' % (count, reason[:200]))
EOF
}

# run NAME DIRECTORY [flutter test arguments]: one run, its report read back.
run() {
  name="$1"; where="$2"; shift 2
  take_turn
  quiet
  began="$(date +%s)"
  rm -f "$out/$name.json"
  (cd "$where" && flutter test --no-pub --concurrency=2 --reporter failures-only --file-reporter "json:$out/$name.json" "$@") >"$out/$name.log" 2>&1
  code=$?
  said="$(report "$out/$name.json")"
  counts="$(echo "$said" | head -1)"
  say "$name: $counts ($(( $(date +%s) - began )) s)"
  echo "$said" | sed '1d' | sed 's/^/check: /'
  set -- $counts
  passed=$((passed + ${1:-0})); failures=$((failures + ${3:-0})); skipped=$((skipped + ${5:-0}))
  if [ "$code" -ne 0 ]; then
    failed="$failed $name"
    # A run that died before it reported (the tool itself, a crash) has no failing test to name: its log has why.
    echo "$said" | grep -q FAILED || say "  the run ended $code and named no test; see $out/$name.log"
  fi
}

kit() {
  run kit "$root/packages/glacier"
}

# The folders of test/ that git knows a test in, and "." where there are tests at its top.
folders() {
  git ls-files 'test/*_test.dart' | awk -F/ '{ print (NF > 2 ? $2 : ".") }' | sort -u
}

# The Mac's build of the core is what the Dart tests of it open; one older than its source answers for the old source.
core_note() {
  if [ ! -f "$library" ]; then
    say "note: the Mac's build of the core is not there, so the tests that open it skip themselves (tool/build-native.sh host)"
    return 0
  fi
  newer="$(find native/src native/shims native/Cargo.toml ../glyph/src-tauri/src -type f -newer "$library" 2>/dev/null | head -1)"
  [ -z "$newer" ] || say "note: the Mac's build of the core is older than $newer; the Dart tests of the core ran against the old one (tool/build-native.sh host)"
}

app() {
  if [ $# -eq 0 ]; then
    # shellcheck disable=SC2046
    set -- $(folders)
  fi
  for folder in "$@"; do
    if [ "$folder" = . ]; then
      # shellcheck disable=SC2046
      run app-top "$root" $(git ls-files 'test/*_test.dart' | awk -F/ 'NF == 2')
    elif [ -d "test/$folder" ]; then
      run "app-$folder" "$root" "test/$folder"
    else
      say "app-$folder: there is no test/$folder"
      failed="$failed app-$folder"
    fi
  done
  core_note
}

# What git has must compile by itself. The analyzer reads the working tree, where a file nobody added is as good as
# any other: lib/core/blanks.dart was imported by twenty-two files for two days and was in no commit. So every
# import in the last commit is looked for in that commit ("missing": a clean checkout does not compile), and every
# import in the files as they are now is looked for among what git knows ("unadded": to go in with what needs it).
imports() {
  python3 - "$root" <<'EOF'
import os, re, subprocess, sys

os.chdir(sys.argv[1])
KIT = 'packages/glacier'


def git(*args):
    return subprocess.run(('git',) + args, capture_output=True, text=True).stdout.splitlines()


def resolve(uri, source):
    if uri.startswith('package:ghost_md/'):
        return 'lib/' + uri[len('package:ghost_md/'):]
    if uri.startswith('package:glacier/'):
        return KIT + '/lib/' + uri[len('package:glacier/'):]
    if ':' in uri:
        return None
    return os.path.normpath(os.path.join(os.path.dirname(source), uri))


def imported(lines, head):
    found = {}
    for line in lines:
        parts = line.split(':', 3 if head else 2)
        path, said = parts[-3], parts[-1]
        if not path.endswith('.dart') or re.match(r'\s*part\s+of\b', said):
            continue
        for uri in re.findall(r'''['"]([^'"]+)['"]''', said):
            target = resolve(uri, path)
            if target and target.endswith('.dart'):
                found.setdefault(target, []).append(path)
    return found


directive = r'^[[:space:]]*(import|export|part)[[:space:]]'
committed = set(git('ls-tree', '-r', '--name-only', 'HEAD'))
for target, by in sorted(imported(git('grep', '-n', '-E', directive, 'HEAD', '--', 'lib', 'test', KIT), True).items()):
    if target not in committed:
        print('missing %s %d %s' % (target, len(by), by[0]))
known = set(git('ls-files'))
for target, by in sorted(imported(git('grep', '-n', '-E', directive, '--', 'lib', 'test', KIT), False).items()):
    if target not in known and os.path.exists(target):
        print('unadded %s %d %s' % (target, len(by), by[0]))
EOF
}

analyze() {
  take_turn
  quiet
  held_back="$(imports)"
  if echo "$held_back" | grep -q '^missing '; then
    failed="$failed imports"
    echo "$held_back" | awk '$1 == "missing" { printf "check: imports: the last commit has no %s, which %d of its files import (%s): a clean checkout does not compile\n", $2, $3, $4 }'
  else
    say "imports: every file the last commit imports is in it"
  fi
  echo "$held_back" | awk '$1 == "unadded" { printf "check: note: %s is not in git yet, and %s imports it: it goes in with the commit that needs it\n", $2, $4 }'
  flutter analyze --no-pub lib test packages/glacier >"$out/analyze.log" 2>&1
  errors="$(grep -c '^ *error •' "$out/analyze.log")"
  warnings="$(grep -c '^ *warning •' "$out/analyze.log")"
  infos="$(grep -c '^ *info •' "$out/analyze.log")"
  say "analyze: $errors errors, $warnings warnings, $infos infos"
  if [ "$errors" -ne 0 ] || [ "$warnings" -ne 0 ]; then
    failed="$failed analyze"
    grep -E '^ *(error|warning) •' "$out/analyze.log" | sed 's/^ */check:   /'
  elif ! grep -q 'issues\{0,1\} found' "$out/analyze.log"; then
    # Neither a count nor a clean bill: the analyzer did not finish.
    failed="$failed analyze"
    say "  the analyzer did not finish; see $out/analyze.log"
  fi
  # The two the analyzer cannot read and Dart can (`\p{Extended_Pictographic}` under `unicode: true`, held by
  # test/plugins) are left; any other is worth a look.
  grep '^ *info •' "$out/analyze.log" | grep -v 'valid_regexps' | sed 's/^ */check:   /'
}

# test/e2e and test/live against the real service on 127.0.0.1, each folder against a service of its own, begun
# empty: the service lets one address in twenty times a minute (../glyph/server/src/accounts.rs), every device of
# every test is this Mac, and two folders at one service spend each other's turns.
server() {
  take_turn
  build_turn
  tool/local-server.sh build >"$out/server-build.log" 2>&1
  code=$?
  built
  if [ "$code" -ne 0 ]; then
    say "server: the service did not build; see $out/server-build.log"
    failed="$failed server"
    return 0
  fi
  for folder in e2e live; do
    quiet
    theirs=""
    tool/local-server.sh status >/dev/null 2>&1 && theirs=1
    [ -z "$theirs" ] || say "note: a local service was already running; it is used as it is and left running, and whoever else is asking it shares its sign-ins"
    if ! tool/local-server.sh start >"$out/server-$folder.start" 2>&1; then
      say "server-$folder: the local service did not start; see $out/server-$folder.start"
      failed="$failed server-$folder"
      continue
    fi
    [ -n "$theirs" ] || serving=1
    # shellcheck disable=SC1091
    . "$root/build/local-server/run.env"
    export GHOST_E2E_API GHOST_E2E_DATA
    run "server-$folder" "$root" "test/$folder"
    unset GHOST_E2E_API GHOST_E2E_DATA
    [ -n "$theirs" ] || tool/local-server.sh stop >/dev/null 2>&1
    serving=""
  done
}

native() {
  take_turn
  quiet
  say "native: cargo's tests, $jobs jobs (waiting for the build lock first)"
  build_turn
  began="$(date +%s)"
  GHOST_JOBS="$jobs" tool/build-native.sh test >"$out/native.log" 2>&1
  code=$?
  built
  grep '^test result:' "$out/native.log" | awk '{ p += $4; f += $6; i += $8 } END { printf "check: native: %d passed, %d failed, %d ignored in %d test binaries", p, f, i, NR }'
  echo " ($(( $(date +%s) - began )) s)"
  if [ "$code" -ne 0 ]; then
    failed="$failed native"
    grep -E '^test .* \.\.\. FAILED|^error' "$out/native.log" | sed 's/^/check:   /'
    say "  see $out/native.log"
  fi
}

pictures() {
  changed="$(git status --short -- '*.png' | grep -v '/failures/' || true)"
  if [ -n "$changed" ]; then
    say "pictures changed and not committed (look at each beside \`git show HEAD:<path>\` before it is kept):"
    echo "$changed" | sed 's/^/check:   /'
  else
    say "no picture changed"
  fi
}

# What the files changed since a commit can reach: "kit <why>", "folder <name> <why>", "all <why>", "native <why>",
# "changed <how many>", a line each. <why> is one changed file that reaches it.
touched() {
  python3 - "$root" "$1" <<'EOF'
import os, re, subprocess, sys

root, rev = sys.argv[1], sys.argv[2]
os.chdir(root)
KIT = 'packages/glacier'


def git(*args):
    done = subprocess.run(('git',) + args, capture_output=True, text=True)
    if done.returncode != 0:
        sys.stderr.write(done.stderr)
        sys.exit(3)
    return [line for line in done.stdout.splitlines() if line]


if os.environ.get('GHOST_CHECK_FILES'):
    changed = sorted(set(os.environ['GHOST_CHECK_FILES'].split()))
else:
    changed = sorted(set(git('diff', '--name-only', rev, '--') + git('ls-files', '--others', '--exclude-standard')))

# Every Dart file a test can compile: the app's, the kit's, and both sets of tests (known to git or not).
dart = []
for top in ('lib', 'test', KIT + '/lib', KIT + '/test'):
    for folder, _, names in os.walk(top):
        dart += [os.path.join(folder, name) for name in names if name.endswith('.dart')]
known = set(dart)

directive = re.compile(r'''^\s*(?:import|export|part)\s+(?!of\b)([^;]*);''', re.M)
quoted = re.compile(r'''(?:'((?:[^'\\\n]|\\.)*)'|"((?:[^"\\\n]|\\.)*)")''')
opened = re.compile(r'''\b(?:File|Directory)\(\s*r?['"]([^'"$\n]+)['"]''')


def resolve(uri, source):
    if uri.startswith('package:ghost_md/'):
        return 'lib/' + uri[len('package:ghost_md/'):]
    if uri.startswith('package:glacier/'):
        return KIT + '/lib/' + uri[len('package:glacier/'):]
    if ':' in uri:
        return None
    return os.path.normpath(os.path.join(os.path.dirname(source), uri))


importers = {}   # a file -> the files that import it, export it or are made of it
names = {}       # a path in the repository -> the Dart files that name it in a string: a file, or a folder of them
core = set()     # the tests that open the Mac's build of the Rust core
for source in dart:
    try:
        text = open(source, encoding='utf-8').read()
    except (OSError, UnicodeDecodeError):
        continue
    for found in directive.finditer(text):
        for one in quoted.finditer(found.group(1)):
            target = resolve(one.group(1) or one.group(2) or '', source)
            if target:
                importers.setdefault(target, set()).add(source)
    # The strings that are paths in the repository, from where a test runs (the kit's from its own folder too). An
    # import's address is not one; a string a `$name` cuts short names the folder it was in.
    bases = ['', KIT] if source.startswith(KIT + '/') else ['']
    body = directive.sub('', text)
    bare = set(opened.findall(body))
    literals = {(name, False) for name in bare}
    for found in quoted.finditer(body):
        whole = found.group(1) if found.group(1) is not None else found.group(2)
        literals.add((whole.split('$')[0], '$' in whole))
    for literal, cut in literals:
        if literal.startswith('native/target/'):
            core.add(source)
            continue
        if len(literal) < 3 or ' ' in literal or ':' in literal or ('/' not in literal and literal not in bare):
            continue
        for base in bases:
            path = os.path.normpath(os.path.join(base, literal))
            if path.startswith(('..', '/', 'build/', '.dart_tool')) or path in ('.', 'build'):
                continue
            if cut and not os.path.exists(path) and '/' in path:
                path = os.path.dirname(path)
            if os.path.exists(path):
                names.setdefault(path, set()).add(source)

everything = None
reason = {}      # a Dart file reached -> the changed file that reached it
queue = []


def reach(target, by):
    if target not in reason:
        reason[target] = by
        queue.append(target)


for path in changed:
    if path in ('pubspec.yaml', 'pubspec.lock', KIT + '/pubspec.yaml') or path.startswith(('assets/', 'shaders/')):
        # What every test draws with: the packages, the faces, the stylesheets, the shaders.
        everything = everything or path
    if path.startswith('native/') or path == 'tool/build-native.sh':
        for source in core:
            reach(source, path)
    if path in known or path in importers:
        reach(path, path)
    at = path
    while at:
        for source in names.get(at, ()):
            reach(source, path)
        at = os.path.dirname(at)
while queue:
    at = queue.pop()
    for source in importers.get(at, ()):
        reach(source, reason[at])

kit, folders = None, {}
for path in changed:
    if path.startswith(KIT + '/') and not path.endswith('.dart'):
        kit = kit or path
    parts = path.split('/')
    if parts[0] == 'test' and len(parts) > 2 and not path.endswith('.dart') and 'failures' not in parts:
        folders.setdefault(parts[1], path)
for path in sorted(reason):
    if not path.endswith('_test.dart'):
        continue
    if path.startswith(KIT + '/test/'):
        kit = kit or reason[path]
    elif path.startswith('test/'):
        parts = path.split('/')
        folders.setdefault(parts[1] if len(parts) > 2 else '.', reason[path])

print('changed %d' % len(changed))
if everything:
    print('all %s' % everything)
if kit or everything:
    print('kit %s' % (kit or everything))
for folder in sorted(folders):
    print('folder %s %s' % (folder, folders[folder]))
for path in changed:
    if path.startswith('native/') or path == 'tool/build-native.sh':
        print('native %s' % path)
        break
EOF
}

# The quick one: what changed since a commit, the kit and the folders it reaches, the analyzer.
since() {
  rev="$1"; list="$2"
  if ! git rev-parse --verify --quiet "$rev^{commit}" >/dev/null; then
    say "there is no commit called $rev"
    exit 2
  fi
  reached="$(touched "$rev")" || { say "what changed since $rev could not be read"; exit 2; }
  known="$(folders)"
  all="$(echo "$reached" | awk '$1 == "all" { print $2 }')"
  kit_why="$(echo "$reached" | awk '$1 == "kit" { print $2 }')"
  native_why="$(echo "$reached" | awk '$1 == "native" { print $2 }')"
  say "since $rev: $(echo "$reached" | awk '$1 == "changed" { print $2 }') files changed"
  todo=""
  if [ -n "$all" ]; then
    say "  everything, by $all"
    todo="$known"
  else
    for folder in $(echo "$reached" | awk '$1 == "folder" { print $2 }'); do
      why="$(echo "$reached" | awk -v f="$folder" '$1 == "folder" && $2 == f { print $3 }')"
      if echo "$known" | grep -qx -- "$folder"; then
        todo="$todo $folder"
        [ -z "$list" ] || say "  test/$folder, by $why"
      else
        say "  NOT test/$folder (git knows no test in it), reached by $why"
      fi
    done
  fi
  [ -z "$kit_why" ] || [ -z "$list" ] || say "  the kit, by $kit_why"
  # shellcheck disable=SC2086
  say "  to run:${kit_why:+ the kit,} $(echo $todo | wc -w | tr -d ' ') of $(echo "$known" | wc -l | tr -d ' ') folders (${todo:+$(echo $todo)}), the analyzer"
  if [ -z "$list" ]; then
    [ -z "$kit_why" ] || kit
    # shellcheck disable=SC2086
    [ -z "$todo" ] || app $todo
    analyze
    pictures
  fi
  if echo " $todo " | grep -Eq ' (e2e|live) '; then
    say "note: --since does not start the service: the halves of test/e2e and test/live that need it were skipped (tool/check.sh server)"
  fi
  [ -z "$native_why" ] || say "note: $native_why changed: cargo's own tests are \`tool/check.sh native\`, and the Dart tests open the core as tool/build-native.sh host last built it"
}

what="${1:-all}"
[ $# -gt 0 ] && shift
case "$what" in
  kit) kit ;;
  app) app "$@" ;;
  test) run test "$root" "$@" ;;
  analyze) analyze ;;
  server) server ;;
  native) native ;;
  pictures) pictures ;;
  --since | --quick)
    rev=HEAD
    if [ "$what" = --since ]; then
      [ $# -gt 0 ] || { say "--since wants a commit: tool/check.sh --since <rev>"; exit 2; }
      rev="$1"; shift
    fi
    list=""
    [ "${1:-}" = --list ] && list=1
    since "$rev" "$list"
    [ -z "$list" ] || exit 0
    ;;
  --list) say "the kit, then: $(folders | tr '\n' ' ')" ; exit 0 ;;
  all) kit; app; analyze; server; native; pictures ;;
  *) sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 2 ;;
esac

[ "$passed$failures$skipped" = 000 ] || say "in all: $passed passed, $failures failed, $skipped skipped"
if [ -n "$failed" ]; then
  say "FAILED:$failed"
  exit 1
fi
say "nothing failed"
