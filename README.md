# zsh-inline-history-search

> Inline history search with ghost-text completion for Zsh — the cursor position governs the match prefix.

---

## Features

- **Cursor-governed prefix** — the search prefix is always everything to the *left* of the cursor, not the entire buffer. Move the cursor left/right to narrow or broaden the match.
- **Ghost text** — matching history entries are shown inline in a dim color *after* the cursor, without altering the buffer.
- **Cycle through matches** — Up/Down arrows cycle through all matching history entries (most recent first) without moving the cursor.
- **Accept one character** — Right arrow accepts the first character of the ghost text and recalculates suggestions for the longer prefix.
- **Accept all** — Tab accepts the entire ghost text in one keystroke.
- **Configurable highlight style** — color and style (bold, italic, …) are fully customizable via a single variable.
- **Zero external dependencies** — pure Zsh, no third-party tools required.

---

## Demo

Assume the following history (most recent last):

```
ls daino
ls demente
ls dev
ls dependencies
ls diluvio
```

```
$ ls d█                   # cursor after 'd', ghost text: iluvio
$ ls d█iluvio             # press ↑ → ghost: ependencies
$ ls d█ependencies        # press ↑ → ghost: ev
$ ls d█ev                 # press → → accepts 'e', buffer: 'ls de', ghost: v
$ ls de█v                 # press ← → cursor back, prefix 'ls d', ghost: iluvio
$ ls d█iluvio             # press Tab → accepts entire suggestion
$ ls diluvio█
```

(`█` marks the cursor position; text after `█` is ghost text shown in dim gray.)

---

## Installation

### Manual

```zsh
mkdir -p ~/.zsh/plugins/zsh-inline-history-search
curl -o ~/.zsh/plugins/zsh-inline-history-search/zsh-inline-history-search.plugin.zsh \
  https://raw.githubusercontent.com/tagliala/zsh-inline-history-search/main/zsh-inline-history-search.plugin.zsh
```

Add to `~/.zshrc`:

```zsh
source ~/.zsh/plugins/zsh-inline-history-search/zsh-inline-history-search.plugin.zsh
```

### Oh My Zsh

```zsh
git clone https://github.com/tagliala/zsh-inline-history-search \
  ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-inline-history-search
```

Add `zsh-inline-history-search` to the `plugins` array in `~/.zshrc`:

```zsh
plugins=(... zsh-inline-history-search)
```

### Antigen

```zsh
antigen bundle tagliala/zsh-inline-history-search
```

### Zinit

```zsh
zinit light tagliala/zsh-inline-history-search
```

### zplug

```zsh
zplug "tagliala/zsh-inline-history-search"
```

---

## Usage

| Key | Action |
|---|---|
| **↑ Up arrow** | Cycle backward through history entries matching the current prefix (everything left of cursor). Ghost text appears in dim color after the cursor. |
| **↓ Down arrow** | Cycle forward (toward more recent matches). Reaching the bottom returns to the original typed text with no suggestion. |
| **→ Right arrow** | Accept **one character** from the ghost text. The prefix grows by one letter and matches are recalculated. |
| **← Left arrow** | Move cursor back one position. The prefix shrinks and matches are recalculated for the shorter prefix. |
| **Tab** | Accept the **entire** suggestion (ghost text is appended to the buffer). |
| **Enter** | Clear ghost text and execute the command as typed in the buffer. |
| **Any printable character** | Insert character at the cursor position and recalculate the suggestion from the new prefix. |
| **Backspace** | Delete the character before the cursor and recalculate the suggestion. |

---

## Configuration

The ghost-text highlight style is controlled by the `INLINE_HISTORY_SEARCH_HIGHLIGHT` variable. Set it *before* sourcing the plugin (or at any point in `~/.zshrc`):

```zsh
# Default: dim gray (terminal color 8)
INLINE_HISTORY_SEARCH_HIGHLIGHT='fg=8'

# Medium gray
INLINE_HISTORY_SEARCH_HIGHLIGHT='fg=240'

# Light gray, italic
INLINE_HISTORY_SEARCH_HIGHLIGHT='fg=245,italic'
```

The value is passed directly to Zsh's `region_highlight`, so it supports all attributes: `fg=`, `bg=`, `bold`, `italic`, `underline`, `standout`, etc.

---

## How it works

The core idea is that **the cursor position governs the search prefix**.

When you press ↑ or ↓, the plugin reads `BUFFER[1,$CURSOR]` — everything left of the cursor — as the pattern to match against history. The matched portion that extends *beyond* the prefix is displayed as ghost text using Zsh's built-in `POSTDISPLAY` variable and highlighted with `region_highlight`.

Because the prefix is derived from the cursor position rather than the full buffer:

- Pressing **←** shrinks the prefix and immediately widens the set of possible matches.
- Pressing **→** (accept one char) grows the prefix and narrows the matches.
- Pressing **Tab** appends the entire ghost text and places the cursor at the end.

Matches are collected by iterating over the `$history` associative array from most recent to oldest, filtering entries that start with the current prefix, deduplicating, and skipping entries that are exact copies of the prefix (nothing to suggest).

---

## License

[MIT](LICENSE) © 2026 Taglialatela Stefano
