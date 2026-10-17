#!/data/data/com.termux/files/usr/bin/bash
# Shared helpers for the TAD (tad-*) scripts. Sourced, not run.

set -euo pipefail

# ---------------------------------------------------------------------------
# Locate the toolchain root, resolving symlinks (scripts live in ~/.local/bin)
# ---------------------------------------------------------------------------
_tad_self="${BASH_SOURCE[0]}"
command -v readlink >/dev/null 2>&1 && _tad_self="$(readlink -f "$_tad_self" 2>/dev/null || echo "$_tad_self")"
# Always derive the root from the script's own location. TAD_ROOT must never be
# inherited: a copy exported into the environment by an older env.sh would
# otherwise override where this copy actually lives.
TAD_ROOT="$(cd "$(dirname "$_tad_self")/.." && pwd)"
TAD_CONF="$TAD_ROOT/tad.conf"
TAD_ENV="$TAD_ROOT/env.sh"
TAD_BIN="$TAD_ROOT/bin"
TAD_TEMPLATES="$TAD_ROOT/templates"

: "${PREFIX:=/data/data/com.termux/files/usr}"

# ---------------------------------------------------------------------------
# Output
# ---------------------------------------------------------------------------
# Colour unless NO_COLOR is set; FORCE_COLOR keeps it on when output is piped.
if [ -n "${FORCE_COLOR:-}" ] || { [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; }; then
  _r=$'\033[0m'; _b=$'\033[1m'; _dim=$'\033[2m'
  _red=$'\033[31m'; _grn=$'\033[32m'; _ylw=$'\033[33m'
  _blu=$'\033[34m'; _mag=$'\033[35m'; _cyn=$'\033[36m'
else
  _r=; _b=; _dim=; _red=; _grn=; _ylw=; _blu=; _mag=; _cyn=
fi

# --- output ----------------------------------------------------------------
step()  { printf '%s▸%s %s%s%s\n' "$_cyn" "$_r" "$_b" "$*" "$_r"; }
info()  { printf '  %s%s%s\n' "$_dim" "$*" "$_r"; }
ok()    { printf '  %s✓%s %s\n' "$_grn" "$_r" "$*"; }
warn()  { printf '  %s!%s %s\n' "$_ylw" "$_r" "$*" >&2; }
err()   { printf '  %s✗%s %s\n' "$_red" "$_r" "$*" >&2; }
die()   { err "$*"; exit 1; }
kv()    { printf '  %s%-13s%s %s\n' "$_dim" "$1" "$_r" "$2"; }
title() { printf '\n%s%s%s\n' "$_b" "$*" "$_r"; }
group() { printf '\n  %s%s%s\n' "$_b$_mag" "$*" "$_r"; }
cmdrow() { printf '    %s%-11s%s %s\n' "$_cyn" "$1" "$_r" "$2"; }
_tad_hr="────────────────────────────────────────────────────────"
hr()    { printf '%s%s%s\n' "$_dim" "$_tad_hr" "$_r"; }

confirm() {
  local reply
  printf '%s [y/N] ' "$1"
  read -r reply || reply=""
  case "$reply" in [yY]|[yY][eE][sS]) return 0 ;; *) return 1 ;; esac
}

# ---------------------------------------------------------------------------
# Config / environment
# ---------------------------------------------------------------------------
load_conf() {
  [ -f "$TAD_CONF" ] || die "missing config: $TAD_CONF"
  # shellcheck disable=SC1090
  . "$TAD_CONF"
  # Platform id including the optional minor level, e.g. "37.2" or "36".
  SDK_PLATFORM="${COMPILE_SDK}${COMPILE_SDK_MINOR:+.$COMPILE_SDK_MINOR}"
}

load_env() {
  if [ -f "$TAD_ENV" ]; then
    # shellcheck disable=SC1090
    . "$TAD_ENV"
  fi
  export ANDROID_HOME="${ANDROID_HOME:-$HOME/android-sdk}"
  export ANDROID_SDK_ROOT="${ANDROID_SDK_ROOT:-$ANDROID_HOME}"
  if [ -z "${JAVA_HOME:-}" ]; then
    local jv
    for jv in "$PREFIX"/lib/jvm/java-*-openjdk; do
      [ -d "$jv" ] && JAVA_HOME="$jv"
    done
    [ -n "${JAVA_HOME:-}" ] && export JAVA_HOME
  fi
  # Only Termux's aarch64 tools and the SDK's Java-based cmdline-tools belong on
  # PATH. platform-tools/build-tools also ship x86-64 native binaries (adb,
  # aapt2) that cannot execute here, so they are deliberately excluded to avoid
  # shadowing the working Termux copies.
  local p="$PREFIX/bin:$HOME/.local/bin"
  [ -n "${JAVA_HOME:-}" ] && p="$JAVA_HOME/bin:$p"
  export PATH="$p:$ANDROID_HOME/cmdline-tools/latest/bin:$PATH"
  return 0
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "missing command '$1'${2:+ — $2}"
}

pkg_installed() {
  pkg list-installed 2>/dev/null | awk -F/ '{print $1}' | grep -qx "$1"
}

in_termux() {
  [ -n "${TERMUX_VERSION:-}" ] || [ -d "$PREFIX" ]
}

# ---------------------------------------------------------------------------
# Gradle helpers
# ---------------------------------------------------------------------------
# Which Gradle to invoke. On-device the Termux 'gradle' package already
# satisfies the pinned version, so prefer it and avoid re-downloading a full
# Gradle distribution through the wrapper. TAD_GRADLE=wrapper forces ./gradlew;
# TAD_GRADLE=system forces the Termux gradle.
gradle_cmd() {
  local pref="${TAD_GRADLE:-auto}"
  if [ "$pref" = wrapper ] && [ -x ./gradlew ]; then echo ./gradlew; return 0; fi
  if [ "$pref" != wrapper ] && command -v gradle >/dev/null 2>&1; then echo gradle; return 0; fi
  if [ -x ./gradlew ]; then echo ./gradlew; return 0; fi
  echo gradle
}

gradle_run() {
  local g; g="$(gradle_cmd)"
  [ "$g" = "gradle" ] && require_cmd gradle "install the Termux 'gradle' package"
  "$g" "$@"
}

# find_apk <debug|release> — newest matching APK from any module. Never fails:
# returns an empty string when nothing matches (callers test for emptiness).
find_apk() {
  local variant="${1:-debug}"
  find . -type f -path '*/build/outputs/apk/*' -name "*${variant}*.apk" 2>/dev/null \
    | sort | tail -n1 || true
}

# Verify an APK really contains its pieces — Gradle can print BUILD SUCCESSFUL
# yet emit an APK with no manifest/arsc when aapt2 is unhappy.
apk_verify() {
  local apk="$1" rc=0
  [ -f "$apk" ] || { err "APK not found: $apk"; return 1; }
  step "Verifying $(basename "$apk")"
  if command -v unzip >/dev/null 2>&1; then
    local listing; listing="$(unzip -l "$apk" 2>/dev/null || true)"
    local entry
    for entry in AndroidManifest.xml resources.arsc; do
      if printf '%s' "$listing" | grep -q " $entry\$"; then ok "$entry present"
      else err "$entry MISSING (false 'BUILD SUCCESSFUL' possible)"; rc=1; fi
    done
    if printf '%s' "$listing" | grep -qE ' classes[0-9]*\.dex$'; then ok "dex present"
    else err "classes*.dex MISSING"; rc=1; fi
  else
    warn "unzip not installed; skipping APK content check"
  fi
  if command -v apksigner >/dev/null 2>&1; then
    if apksigner verify "$apk" >/dev/null 2>&1; then ok "signature valid"
    else warn "apksigner could not verify the APK"; fi
  fi
  return $rc
}

# ---------------------------------------------------------------------------
# adb helpers
# ---------------------------------------------------------------------------
adb_ensure() {
  require_cmd adb "install the Termux 'android-tools' package"
  adb start-server >/dev/null 2>&1 || true
  if ! adb devices | awk 'NR>1 && $2=="device"{n++} END{exit !(n>0)}'; then
    die "no adb device connected — run: tad-adb connect"
  fi
}

adb_serial() {
  adb devices | awk 'NR>1 && $2=="device"{print $1; exit}'
}
