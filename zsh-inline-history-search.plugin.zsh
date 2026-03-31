#!/usr/bin/env zsh
#
# zsh-inline-history-search
#
# Inline history search with ghost-text completion.
# The cursor position governs the search prefix — everything to the left of
# the cursor is the prefix used for history matching.
#
# Up/Down arrows cycle through matching history entries without moving the
# cursor. Right arrow accepts one character, Tab accepts the full suggestion.
# Left arrow moves the cursor back and recalculates matches for the shorter prefix.
#

#-----------------------------------------------------------------------------
# Configuration
#-----------------------------------------------------------------------------

: ${INLINE_HISTORY_SEARCH_HIGHLIGHT:='fg=8'}

#-----------------------------------------------------------------------------
# Internal state
#-----------------------------------------------------------------------------

typeset -g _ihs_suggestion         # Current full suggestion from history
typeset -g -a _ihs_matches        # Array of matching history entries
typeset -g -i _ihs_match_index    # Current index into _ihs_matches (1-based)
typeset -g -i _ihs_active         # Whether we are in search mode
typeset -g _ihs_last_prefix       # Last prefix used for search (cache)
typeset -g _IHS_LAST_HIGHLIGHT    # Last region_highlight entry we added

#-----------------------------------------------------------------------------
# Core: find matches for the given prefix
#-----------------------------------------------------------------------------

_ihs_find_matches() {
  local prefix="$1"
  _ihs_matches=()
  _ihs_last_prefix="$prefix"

  [[ -z "$prefix" ]] && return

  # Escape glob characters in the prefix
  local escaped="${prefix//(#m)[]\\*?[<>()|^~#!]/\\$MATCH}"

  local -A seen
  local key entry
  local -i match_limit=200

  # Walk history from most recent to oldest
  for key in "${(@k)history}"; do
    entry="$history[$key]"

    # Must start with our prefix
    [[ "$entry" == ${~escaped}* ]] || continue

    # Skip exact match (no completion to offer)
    [[ "$entry" == "$prefix" ]] && continue

    # Skip duplicates (O(1) with associative array)
    (( ${+seen[$entry]} )) && continue
    seen[$entry]=1

    _ihs_matches+=("$entry")

    # Cap the number of collected matches
    (( ${#_ihs_matches} >= match_limit )) && break
  done
}

#-----------------------------------------------------------------------------
# Core: refresh matches if the current prefix has changed
#-----------------------------------------------------------------------------

_ihs_refresh_if_needed() {
  local prefix="${BUFFER[1,$CURSOR]}"
  if [[ "$prefix" != "$_ihs_last_prefix" ]]; then
    _ihs_find_matches "$prefix"
    _ihs_match_index=0
    if (( ${#_ihs_matches} > 0 )); then
      _ihs_match_index=1
      _ihs_suggestion="${_ihs_matches[1]}"
    else
      _ihs_suggestion=""
    fi
  fi
}

#-----------------------------------------------------------------------------
# Core: render ghost text via POSTDISPLAY and region_highlight
#-----------------------------------------------------------------------------

_ihs_show_suggestion() {
  local prefix="${BUFFER[1,$CURSOR]}"

  if [[ -n "$_ihs_suggestion" ]]; then
    POSTDISPLAY="${_ihs_suggestion#$prefix}"
  else
    POSTDISPLAY=""
  fi

  # Remove our previous highlight entry
  if [[ -n "$_IHS_LAST_HIGHLIGHT" ]]; then
    region_highlight=("${(@)region_highlight:#$_IHS_LAST_HIGHLIGHT}")
    _IHS_LAST_HIGHLIGHT=""
  fi
  if (( $#POSTDISPLAY )); then
    _IHS_LAST_HIGHLIGHT="$#BUFFER $(( $#BUFFER + $#POSTDISPLAY )) $INLINE_HISTORY_SEARCH_HIGHLIGHT"
    region_highlight+=("$_IHS_LAST_HIGHLIGHT")
  fi

  zle -R
}

#-----------------------------------------------------------------------------
# Core: clear all ghost-text state
#-----------------------------------------------------------------------------

_ihs_clear() {
  POSTDISPLAY=""
  if [[ -n "$_IHS_LAST_HIGHLIGHT" ]]; then
    region_highlight=("${(@)region_highlight:#$_IHS_LAST_HIGHLIGHT}")
    _IHS_LAST_HIGHLIGHT=""
  fi
  _ihs_active=0
  _ihs_suggestion=""
  _ihs_matches=()
  _ihs_match_index=0
  _ihs_last_prefix=""
  zle -R
}

#-----------------------------------------------------------------------------
# Widget: search up (cycle to older matches)
#-----------------------------------------------------------------------------

_ihs_search_up() {
  emulate -L zsh
  setopt EXTENDED_GLOB

  if (( ! _ihs_active )); then
    local prefix="${BUFFER[1,$CURSOR]}"
    _ihs_find_matches "$prefix"
    _ihs_match_index=0
    _ihs_active=1
  else
    _ihs_refresh_if_needed
  fi

  if (( ${#_ihs_matches} == 0 )); then
    _ihs_suggestion=""
    _ihs_show_suggestion
    return
  fi

  if (( _ihs_match_index < ${#_ihs_matches} )); then
    (( _ihs_match_index++ ))
  fi

  _ihs_suggestion="${_ihs_matches[$_ihs_match_index]}"
  _ihs_show_suggestion
}

#-----------------------------------------------------------------------------
# Widget: search down (cycle to more recent matches)
#-----------------------------------------------------------------------------

_ihs_search_down() {
  emulate -L zsh
  setopt EXTENDED_GLOB

  (( _ihs_active )) || return

  _ihs_refresh_if_needed

  if (( _ihs_match_index > 1 )); then
    (( _ihs_match_index-- ))
    _ihs_suggestion="${_ihs_matches[$_ihs_match_index]}"
  else
    # Back to the original typed text, no suggestion
    _ihs_match_index=0
    _ihs_suggestion=""
  fi

  _ihs_show_suggestion
}

#-----------------------------------------------------------------------------
# Widget: right arrow — accept one character from ghost text
#-----------------------------------------------------------------------------

_ihs_accept_char() {
  emulate -L zsh
  setopt EXTENDED_GLOB

  if (( _ihs_active )) && [[ -n "$POSTDISPLAY" ]]; then
    local next_char="${POSTDISPLAY[1]}"
    local prefix="${BUFFER[1,$CURSOR]}"
    BUFFER="${prefix}${next_char}"
    CURSOR=$#BUFFER
    POSTDISPLAY=""

    # Re-search with the new longer prefix
    _ihs_find_matches "${BUFFER[1,$CURSOR]}"
    _ihs_match_index=0
    if (( ${#_ihs_matches} > 0 )); then
      _ihs_match_index=1
      _ihs_suggestion="${_ihs_matches[1]}"
    else
      _ihs_suggestion=""
    fi
    _ihs_show_suggestion
  else
    _ihs_clear
    zle forward-char
  fi
}

#-----------------------------------------------------------------------------
# Widget: left arrow — move cursor back, shrink prefix, recalculate matches
#-----------------------------------------------------------------------------

_ihs_backward_char() {
  emulate -L zsh
  setopt EXTENDED_GLOB

  if (( CURSOR > 0 )); then
    (( CURSOR-- ))
  fi

  if (( _ihs_active )); then
    _ihs_find_matches "${BUFFER[1,$CURSOR]}"
    _ihs_match_index=0
    if (( ${#_ihs_matches} > 0 )); then
      _ihs_match_index=1
      _ihs_suggestion="${_ihs_matches[1]}"
    else
      _ihs_suggestion=""
    fi
    _ihs_show_suggestion
  fi
}

#-----------------------------------------------------------------------------
# Widget: Tab — accept the entire current suggestion
#-----------------------------------------------------------------------------

_ihs_accept_all() {
  emulate -L zsh

  if (( _ihs_active )) && [[ -n "$POSTDISPLAY" ]]; then
    BUFFER="${BUFFER}${POSTDISPLAY}"
    CURSOR=$#BUFFER
    _ihs_clear
  else
    _ihs_clear
    zle expand-or-complete
  fi
}

#-----------------------------------------------------------------------------
# Widget: self-insert — insert character and refresh suggestion
#-----------------------------------------------------------------------------

_ihs_self_insert() {
  emulate -L zsh
  setopt EXTENDED_GLOB

  if (( _ihs_active )); then
    POSTDISPLAY=""
    if [[ -n "$_IHS_LAST_HIGHLIGHT" ]]; then
      region_highlight=("${(@)region_highlight:#$_IHS_LAST_HIGHLIGHT}")
      _IHS_LAST_HIGHLIGHT=""
    fi
  fi

  zle .self-insert

  local prefix="${BUFFER[1,$CURSOR]}"
  _ihs_find_matches "$prefix"
  _ihs_match_index=0
  _ihs_active=0

  if (( ${#_ihs_matches} > 0 )); then
    _ihs_match_index=1
    _ihs_suggestion="${_ihs_matches[1]}"
    _ihs_active=1
  else
    _ihs_suggestion=""
  fi
  _ihs_show_suggestion
}

#-----------------------------------------------------------------------------
# Widget: backspace — delete character and refresh suggestion
#-----------------------------------------------------------------------------

_ihs_backward_delete_char() {
  emulate -L zsh
  setopt EXTENDED_GLOB

  if (( _ihs_active )); then
    POSTDISPLAY=""
    if [[ -n "$_IHS_LAST_HIGHLIGHT" ]]; then
      region_highlight=("${(@)region_highlight:#$_IHS_LAST_HIGHLIGHT}")
      _IHS_LAST_HIGHLIGHT=""
    fi
  fi

  zle .backward-delete-char

  _ihs_active=0
  _ihs_suggestion=""

  if (( $#BUFFER > 0 )); then
    local prefix="${BUFFER[1,$CURSOR]}"
    _ihs_find_matches "$prefix"
    _ihs_match_index=0
    if (( ${#_ihs_matches} > 0 )); then
      _ihs_match_index=1
      _ihs_suggestion="${_ihs_matches[1]}"
      _ihs_active=1
    fi
  fi
  _ihs_show_suggestion
}

#-----------------------------------------------------------------------------
# Widget: Enter — clear ghost text and execute command
#-----------------------------------------------------------------------------

_ihs_accept_line() {
  _ihs_clear
  zle .accept-line
}

#-----------------------------------------------------------------------------
# Register widgets
#-----------------------------------------------------------------------------

zle -N _ihs_search_up
zle -N _ihs_search_down
zle -N _ihs_accept_char
zle -N _ihs_backward_char
zle -N _ihs_accept_all
zle -N _ihs_self_insert
zle -N _ihs_backward_delete_char
zle -N _ihs_accept_line

#-----------------------------------------------------------------------------
# Bind keys
#-----------------------------------------------------------------------------

bindkey '^[[A'  _ihs_search_up             # Up arrow
bindkey '^[OA'  _ihs_search_up             # Up arrow (alternate)
bindkey '^[[B'  _ihs_search_down           # Down arrow
bindkey '^[OB'  _ihs_search_down           # Down arrow (alternate)
bindkey '^[[C'  _ihs_accept_char           # Right arrow
bindkey '^[OC'  _ihs_accept_char           # Right arrow (alternate)
bindkey '^[[D'  _ihs_backward_char         # Left arrow
bindkey '^[OD'  _ihs_backward_char         # Left arrow (alternate)
bindkey '^I'    _ihs_accept_all            # Tab
bindkey '^?'    _ihs_backward_delete_char  # Backspace
bindkey '^H'    _ihs_backward_delete_char  # Backspace (alternate)
bindkey '^M'    _ihs_accept_line           # Enter

# Override self-insert so every printable keystroke refreshes the suggestion
bindkey -M main -R ' '-'~' _ihs_self_insert
