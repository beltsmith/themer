# themer

Tools for developing an Emacs colour theme while you look at it.

## `themer-preview-mode`

Turn it on in a `<name>-theme.el` buffer. After each edit, saved or not, it
re-evaluates the buffer and re-enables the theme (after
`themer-preview-delay`, 0.4s idle by default), so changes to a palette hex
or a role binding show up in every window straight away.

For [autothemer](https://github.com/jasonm23/autothemer) themes, it also
paints each palette and role name with the colour it resolves to, both
where it's defined and wherever a face spec uses it, so you can read the
role → colour mapping straight off the buffer.

- Unbalanced parens mid-edit are skipped.
- If evaluation fails, the previous face settings are restored.
- Turning the mode off removes the swatches. It also disables the theme
  if the theme wasn't already enabled when you turned the mode on.

## `themer-render`, `themer-render-compare`

Render the faces Emacs actually resolved in a buffer (font-lock,
tree-sitter, eglot semantic tokens, all of it) to an SVG. The colours come
from the live face pipeline, not a hand-tagged sample, so the image shows
exactly what the theme does to real code, including the places where one
layer overrides another.

- `themer-render` renders the region, or the visible window if no region
  is active.
- `themer-render-compare` renders font-lock alone next to font-lock plus
  eglot semantic tokens, and underlines every character whose look the
  tokens changed. Use it to spot a semantic-token face clobbering a more
  specific tree-sitter face.

The image opens in `*themer-render*`; press `w` there to write the SVG.

### Headless

```sh
emacs --batch -L path/to/themer -l themer -l setup.el \
      -f themer-batch-render FILE OUT.svg [SETTLE-SECONDS]
```

`setup.el` loads the theme and sets whatever the render depends on:
`treesit-font-lock-level`, the major mode for `FILE`, and
`eglot-server-programs`. If a server is configured for `FILE`'s mode, batch
mode starts eglot itself, waits `SETTLE-SECONDS` (default 3) for the server
to index, and renders the comparison. Otherwise it renders font-lock alone.
Slow-indexing servers such as rust-analyzer need around 20–25 seconds.

To get a PNG: `rsvg-convert OUT.svg -o OUT.png`.

## Options

| Option | Default | |
|---|---|---|
| `themer-preview-delay` | `0.4` | Idle seconds before re-evaluating |
| `themer-render-font-family` | `nil` | `nil` uses the `default` face's family |
| `themer-render-font-size` | `14` | Pixels |
| `themer-render-char-width` | `0.6` | Column width as a fraction of the font size |
| `themer-render-line-height` | `1.45` | Multiple of the font size |
| `themer-render-semtok-timeout` | `10` | Seconds to wait for semantic tokens |
| `themer-render-diff-colour` | `nil` | `nil` uses the `shadow` face |

## Requirements

Emacs 29.1+. The semantic-token comparison needs the eglot that ships with
Emacs 31: it reads eglot's internal `eglot--semtok-state` to tell when
tokens have arrived.
