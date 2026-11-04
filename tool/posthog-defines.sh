#!/bin/sh
# The anonymous usage stats' two defines for a release build (lib/core/metrics.dart, docs/ANALYTICS.md): PostHog's
# project key (phc_..., public: it ships in the app) and its host, read from ~/.config/mattssoftware/posthog.env
# (GHOST_POSTHOG_ENV names another). Sourced by the release scripts, which put "$posthog" on `flutter build`.
#
# Only those two lines are read: the file also holds the personal API key (phx_...), which is the dashboards' script's
# (tool/posthog/setup_dashboards.mjs) and is never sourced, defined or printed here. No file, or no key in it, leaves
# $posthog empty, and the build has no analytics at all.
posthog=""
_posthog_env="${GHOST_POSTHOG_ENV:-$HOME/.config/mattssoftware/posthog.env}"
if [ -f "$_posthog_env" ]; then
  _posthog_key="$(sed -n 's/^[[:space:]]*\(export[[:space:]]*\)\{0,1\}POSTHOG_PROJECT_KEY=["'\'']\{0,1\}\([^"'\'' ]*\).*$/\2/p' "$_posthog_env" | head -1)"
  _posthog_host="$(sed -n 's/^[[:space:]]*\(export[[:space:]]*\)\{0,1\}POSTHOG_HOST=["'\'']\{0,1\}\([^"'\'' ]*\).*$/\2/p' "$_posthog_env" | head -1)"
  case "$_posthog_key" in
    phc_*) posthog="--dart-define=POSTHOG_KEY=$_posthog_key${_posthog_host:+ --dart-define=POSTHOG_HOST=$_posthog_host}" ;;
  esac
fi
if [ -n "$posthog" ]; then echo "Anonymous usage stats: on, to ${_posthog_host:-the default host}." >&2; else echo "Anonymous usage stats: off in this build (no project key in $_posthog_env)." >&2; fi
unset _posthog_env _posthog_key _posthog_host
