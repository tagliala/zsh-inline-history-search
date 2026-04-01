#!/usr/bin/env zsh
#
# Tests for zsh-inline-history-search.
#
# Run with:  zsh test/test_plugin.zsh
#
# ZLE built-ins are stubbed so the plugin can be sourced outside an
# interactive shell.  The tests target _ihs_find_matches and the state
# variables it maintains, which are pure-function enough to exercise
# non-interactively.

REPO_ROOT="${0:A:h:h}"

# Stub ZLE built-ins (unavailable outside an interactive ZLE session).
zle()     { :; }
bindkey() { :; }

source "$REPO_ROOT/zsh-inline-history-search.plugin.zsh" || {
  print -u2 "fatal: failed to source plugin"
  exit 1
}

typeset -ga _zle_calls

zle() {
  case "$1" in
    -N|-R)
      ;;
    .up-line-or-history|.down-line-or-history|.accept-line|.expand-or-complete)
      _zle_calls+=("$1")
      ;;
    .self-insert)
      BUFFER="${BUFFER[1,$CURSOR]}${KEYS}${BUFFER[$(( CURSOR + 1 )),-1]}"
      (( CURSOR += ${#KEYS} ))
      _zle_calls+=("$1")
      ;;
    .backward-delete-char)
      if (( CURSOR > 0 )); then
        BUFFER="${BUFFER[1,$(( CURSOR - 1 ))]}${BUFFER[$(( CURSOR + 1 )),-1]}"
        (( CURSOR-- ))
      fi
      _zle_calls+=("$1")
      ;;
    forward-char)
      if (( CURSOR < $#BUFFER )); then
        (( CURSOR++ ))
      fi
      _zle_calls+=("$1")
      ;;
  esac
}

# ── Test helpers ──────────────────────────────────────────────────────────

typeset -i _pass=0 _fail=0

_ok()  { (( _pass++ )); print "  ok: $1"; }
_nok() {
  (( _fail++ ))
  print "FAIL: $1"
  [[ -n "$2" ]] && print "      expected: $2" && print "      got:      $3"
}

eq() { [[ "$2" == "$3" ]] && _ok "$1" || _nok "$1" "${(qq)2}" "${(qq)3}"; }

_reset_widget_state() {
  BUFFER=""
  CURSOR=0
  POSTDISPLAY=""
  region_highlight=()
  KEYS=""
  _zle_calls=()
  _ihs_clear
}

# ── Set up test history ───────────────────────────────────────────────────

typeset _hist
_hist=$(mktemp)
trap 'rm -f -- "$_hist"' EXIT INT TERM

# Write history in Zsh EXTENDED_HISTORY format.
# The trailing sentinel entry is intentional: Zsh excludes the most-recent
# history event from (@k)history iteration in non-interactive mode, so all
# real test entries remain accessible to _ihs_find_matches.
printf '%s\n' \
  ': 1000000000:0;ls daino'          \
  ': 1000000001:0;ls demente'        \
  ': 1000000002:0;ls dev'            \
  ': 1000000003:0;ls dependencies'   \
  ': 1000000004:0;ls diluvio'        \
  ': 1000000005:0;git status'        \
  ': 1000000006:0;git log --oneline' \
  ': 1000000007:0;echo hello*world'  \
  ': 1000000008:0;ls daino'          \
  ': 1000000009:0;_ihs_test_sentinel' \
  > "$_hist"

HISTFILE="$_hist" HISTSIZE=100 SAVEHIST=100
setopt EXTENDED_GLOB
fc -R "$_hist"

if (( ${#history} == 0 )); then
  print "Bail out! History failed to load via fc -R; cannot run tests."
  exit 1
fi

# ── Tests: _ihs_find_matches ──────────────────────────────────────────────

# 1. Empty prefix yields no matches.
_ihs_find_matches ""
eq "empty prefix yields no matches" "0" "${#_ihs_matches}"

# 2. Prefix matching multiple entries.
_ihs_find_matches "ls d"
eq "'ls d' finds 5 unique entries" "5" "${#_ihs_matches}"

# 3. Narrower prefix returns fewer matches.
_ihs_find_matches "ls di"
eq "'ls di' finds 1 entry" "1" "${#_ihs_matches}"

# 4. The single 'ls di' match is the full command.
eq "'ls di' match is 'ls diluvio'" "ls diluvio" "${_ihs_matches[1]}"

# 5. An entry that exactly equals the prefix is excluded (nothing to suggest).
_ihs_find_matches "ls diluvio"
eq "exact match is excluded from results" "0" "${#_ihs_matches}"

# 6. A prefix with no matching history returns an empty array.
_ihs_find_matches "zzz_no_such_command"
eq "unmatched prefix returns empty array" "0" "${#_ihs_matches}"

# 7. Duplicate history entries appear only once in results.
#    'ls daino' is present twice in the history file.
_ihs_find_matches "ls d"
typeset -i _daino_count=0
for _m in "${_ihs_matches[@]}"; do [[ "$_m" == "ls daino" ]] && (( _daino_count++ )); done
eq "duplicate history entries deduplicated" "1" "$_daino_count"

# 8. A glob metacharacter '*' in the prefix is treated as a literal character.
_ihs_find_matches "echo hello*"
eq "glob metachar '*' in prefix matched literally" "1" "${#_ihs_matches}"

# 9. The literal-glob match returns the correct full entry.
eq "glob literal match returns 'echo hello*world'" "echo hello*world" "${_ihs_matches[1]}"

# 10. Multiple matches for a prefix.
_ihs_find_matches "git"
eq "'git' prefix finds 2 entries" "2" "${#_ihs_matches}"

# 11. _ihs_last_prefix is updated to the searched prefix.
eq "_ihs_last_prefix updated after search" "git" "$_ihs_last_prefix"

# ── Tests: widget behavior ───────────────────────────────────────────────────

# 12. Empty buffer at the start keeps normal Zsh history navigation.
_reset_widget_state
_ihs_search_up
eq "empty buffer uses normal up-line-or-history" ".up-line-or-history" "${_zle_calls[1]}"

# 13. Down at the end of a non-empty buffer still uses normal history when search is inactive.
_reset_widget_state
BUFFER="ls de"
CURSOR=$#BUFFER
_ihs_search_down
eq "down at end uses normal down-line-or-history before search starts" ".down-line-or-history" "${_zle_calls[1]}"

# 14. Up at the end of a non-empty buffer starts inline history search and materializes the selection.
_reset_widget_state
BUFFER="ls de"
CURSOR=$#BUFFER
_ihs_search_up
eq "up at end starts inline search instead of normal history" "0" "${#_zle_calls}"
eq "up at end materializes the first matching history entry" "ls dependencies" "$BUFFER"
eq "materialized suggestion keeps the original cursor position" "5" "$CURSOR"
eq "materialized suggestion does not use ghost text" "" "$POSTDISPLAY"

# 15. Down after an inline search selection restores the originally typed buffer.
_ihs_search_down
eq "down after materialized selection restores original buffer" "ls de" "$BUFFER"
eq "restored buffer also restores the original cursor" "5" "$CURSOR"
eq "down after restoring typed buffer clears active search mode" "0" "$_ihs_active"

# 16. Left on a materialized selection keeps the real buffer text without duplicating ghost output.
_reset_widget_state
BUFFER="ls de"
CURSOR=$#BUFFER
_ihs_search_up
_ihs_backward_char
eq "left on materialized selection keeps the completed buffer" "ls dependencies" "$BUFFER"
eq "left on materialized selection moves the cursor left" "4" "$CURSOR"
eq "left on materialized selection does not create duplicate ghost text" "" "$POSTDISPLAY"

# 17. Typing while a materialized selection is active disables search and edits the actual buffer.
_reset_widget_state
BUFFER="ls de"
CURSOR=$#BUFFER
_ihs_search_up
KEYS="x"
_ihs_self_insert
eq "typing after materializing a selection edits the real buffer" "ls dexpendencies" "$BUFFER"
eq "typing after materializing a selection disables active search" "0" "$_ihs_active"
eq "typing after materializing a selection clears ghost text" "" "$POSTDISPLAY"

# ── Summary ───────────────────────────────────────────────────────────────

print ""
print "Results: $_pass passed, $_fail failed."
(( _fail == 0 ))
