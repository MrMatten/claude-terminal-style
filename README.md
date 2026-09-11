# claude-terminal-style

Centre Claude Code's output in a readable column, and give its UI a coherent
palette — using tmux, Ghostty and Claude Code's own theme system.

Everything is driven from one palette file. Re-running the installer is safe.

## What it does

- **Centres** a single-pane tmux window while `claude` runs in it, using two
  blank padding panes. Adaptive: a window at or below the target width is left
  full width, so laptops and small splits are unaffected.
- **Darkens the pane background** while claude owns the window, lifting contrast
  for everything on screen by roughly 18%. Applied independently of centring, so
  a window too narrow to pad still gets it. Pane borders are painted to match, so
  the padding stays seamless. Cleared when claude exits.
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
    "text_width":          100,               // centre above this, full width at or below
    "claude_background":   "#16161e",         // pane background while claude runs
    "terminal_foreground": "#c7b8b0",         // prose; see "What the theme can reach"
    "ghostty_theme":       "TokyoNight Moon"  // decides how CODE looks (see below)
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

### What the theme can and cannot reach

Verified by static analysis of build 2.1.236. Two findings matter more than the
token list.

**Assistant prose is never given a colour.** The markdown renderer emits no SGR
foreground for paragraphs or headings:

```js
case "paragraph": return htn((e.tokens ?? []).map(p => c3(p, t, {...})).join("")) + jU;
case "text":      { ... return iaw(saw(e, t, r), t, r, n) }   // iaw is identity
```

So prose renders in the **terminal's default foreground**, and the `text` theme
token cannot dim it. `text` does still colour the message bullet, the composer,
and your own echoed prompt. Dim prose by setting the terminal's `foreground`.

**Inline code cannot be themed - this is a bug.** The renderer picks the right
token name, then resolves it against the *un-overridden* built-in palette:

```js
case "codespan": return Vo("permission", t)(e.text);

function Vo(e, t, r = "foreground") { return (n) => {
  if (e.startsWith("rgb(") || e.startsWith("#") || ...) return Lmt(n, e, r);
  return Lmt(n, oae(t)[e], r);        // oae() only knows the six built-in bases
}}
```

`t` is the *base name* ("dark"), not the merged theme, so a custom `permission`
override is parsed, validated, stored - and never consulted. Inline code is
effectively hardcoded to `rgb(177,185,249)` on every base (confirmed present in
both `jcS` and `BcS`). Switching base to `dark-ansi` does **not** help.

The practical consequence: inline code is fixed at `#b1b9f9`, so the only way to
make it stand out is to dim the terminal foreground beneath it. At the default
`#c8d3f5` the contrast is 1.26:1 (invisible); at `#8b93b8` it is 1.61:1.

**The syntax theme is not selectable.** Its name is a pure function of the base:

```js
function Yiw(e){ if(e.includes("ansi")) return "ansi";
                 if(e.includes("dark")) return "Monokai Extended";
                 return "GitHub" }
```

There is no `syntaxTheme` setting; `syntaxHighlightingDisabled` is a kill switch
only. Importantly, the "Syntax theme: ..." line in the `/theme` picker describes
the **diff preview shown above it**, not chat code blocks. The two are disjoint:

| surface | colour source | emission |
|---|---|---|
| fenced blocks in chat | hardcoded hljs→chalk map | basic ANSI → your terminal's 16 colours |
| diffs and file reads | Monokai / GitHub / ansi RGB maps | 24-bit truecolor |

That is why setting the terminal palette makes chat code match your editor, and
why diffs do not follow it.

**Still not reachable by any mechanism:** vertical spacing between blocks,
heading colour or size, code-block backgrounds and borders, table border colour,
blockquote bars, list markers, and font size (terminals are one size).

### Theme tokens

The base theme exposes 144 keys. An override whose key is not one of them is
**silently dropped** - the theme still loads, that key just does nothing:

```js
let l = oae(base);                                // the base theme's colour map
for (let [k, v] of Object.entries(overrides))
  if (Object.hasOwn(l, k) && isValidColour(v)) out[k] = v;
```

The ones worth setting:

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
