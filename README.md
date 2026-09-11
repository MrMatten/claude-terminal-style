# claude-terminal-style

Centre Claude Code's output in a readable column, and give its UI a coherent
palette — using tmux, Ghostty and Claude Code's own theme system.

Everything is driven from one palette file. Re-running the installer is safe.

## What it does

- **Centres** a single-pane tmux window while `claude` runs in it, using two
  blank padding panes. Adaptive: a window at or below the target width is left
  full width, so laptops and small splits are unaffected.
- **Recedes prose** so syntax-highlighted code, bold text and container-backed
  regions stand out by contrast, instead of trying to brighten everything.
- **Themes the UI chrome** — your own messages get a background band, command
  blocks get a border and fill, accents and status colours follow the palette.
- **Matches code colours to your editor** by setting the terminal palette.

## Requirements

tmux 3.2+, Ghostty, Claude Code 2.x, Python 3.

## Install

```sh
./install.sh
```

Then: reload Ghostty with `Cmd+Shift+,` (it does not pick up config changes on
its own), and restart Claude Code once so the timestamp setting takes effect.
The theme itself hot-reloads.

```sh
./install.sh --uninstall   # removes every change, including live tmux padding
```

## Tuning

Edit `palette/nord.json`, then re-run `./install.sh`.

```jsonc
{
  "colors": { "prose": "#a9b1d6", "accent": "#88c0d0", ... },
  "layout": {
    "text_width":     100,               // centre above this, full width at or below
    "pad_background": "#222436",         // padding pane colour; match your terminal bg
    "ghostty_theme":  "TokyoNight Moon"  // decides how CODE looks (see below)
  }
}
```

`generate.py` renders three artifacts into `build/`: the Claude Code theme, a
tmux snippet, and a Ghostty snippet. `install.sh` places them and writes
marker-delimited blocks (`# >>> claude-terminal-style >>>`) into your configs.

## How it works, and why it's split across three tools

Each tool owns the part only it can reach.

| Want | Mechanism | Why not elsewhere |
|---|---|---|
| Centred column | tmux padding panes | Ghostty padding is fixed points and cannot be scripted — no IPC, and `reload_config` is a keybind only. Claude Code has no width setting. |
| Code colours | Ghostty palette | Claude Code's highlighter emits plain ANSI colour *names*, so the terminal decides the actual colours. |
| UI chrome colours | Claude Code theme | Only the theme reaches these tokens. |
| Trigger | Claude Code `SessionStart`/`SessionEnd` hooks + tmux hooks | Session hooks catch every launch path; tmux hooks re-sync on focus and re-attach. |

### Code colours come from the terminal, not the theme

Claude Code highlights with highlight.js and maps token types to **basic ANSI
colour names**, hardcoded in the binary:

```
keyword→blue  built_in→cyan  type→cyan.dim  literal→blue  number→green
regexp→red    string→red     function→yellow  title.function→yellow
title.class→blue  params/symbol/title/subst→reset
```

So the terminal palette is what changes how code looks. Setting Ghostty's theme
to match your editor's gets you the same colours in both — and because editors
generally use truecolor rather than the ANSI palette, retuning those 16 slots
does not change your editor.

The plugin `syntaxHighlighting` component does **not** control colours; it
registers extra highlight.js *grammars* (`{ hljsLanguages: [{id, remote, integrity}] }`).

### What is not possible

Claude Code's theme is a colour map. It has no tokens for markdown elements, so
none of these can be styled by any known mechanism:

- vertical spacing / rhythm between blocks
- headers (colour, weight, or level distinction)
- inline-code backgrounds or "pill" treatment
- fenced code block backgrounds and borders (bash/command blocks are the one
  exception — `bashBorder` and `bashMessageBackgroundColor` exist)
- table border colour, blockquote bars, list markers
- clickable (OSC 8) links
- font size anywhere — terminals are a single-size monospace grid

Recede `text` rather than fight it: everything that *is* coloured then reads as
distinct without needing its own token.

### Theme tokens

Verified against the running binary and working theme files:

```
text  subtle  inactive  inverseText  claude  success  error  warning
suggestion  permission  planMode  autoAccept  autoAcceptShimmer
diffAdded  diffRemoved  diffAddedWord  diffRemovedWord
userMessageBackground  userMessageBackgroundHover  bashMessageBackgroundColor
bashBorder  secondaryBorder  promptBorder  memoryBackgroundColor
composerSidebarBackground  professionalBlue  chromeYellow
rate_limit_fill  rate_limit_empty  fastModeShimmer
```

Values accept `#rrggbb`, `#rgb`, `rgb(r,g,b)`, `ansi256(n)` and `ansi:<name>`.
`ansi:` names follow the terminal palette, which is useful for portability.

Themes live in `~/.claude/themes/<slug>.json` as `{name, base, overrides}` where
`base` inherits a built-in preset (`dark`, `light`, `dark-ansi`, `light-ansi`,
`dark-daltonized`, `light-daltonized`). Claude Code watches the directory and
hot-reloads on save.

## Behaviour notes

- A window you have split is never touched. Splitting a centred window removes
  the padding and returns it to full width.
- `prefix + W` resets one window immediately.
- Padding panes run `cat` with the cursor hidden, so they consume no CPU.
- Borders are painted in the padding colour, so no lines are visible.
- `userMessageBackground` only renders with `tui: "fullscreen"`, which the
  installer sets.
- Narrower output means more line wrapping. If you copy commands out of the
  terminal often, check that wrapped lines paste as single lines in your setup.

## Licence

MIT
