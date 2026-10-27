;;; reader-gruvbox-theme.el --- Gruvbox dark, medium (base16), on the reader standard. -*- lexical-binding: t; -*-

;; A reader-standard theme (research/PATTERNS.md); see `reader-theme-deftheme'.
;; Edit a palette colour and re-evaluate (or use `themer-preview-mode'):
;; every tier is derived again.

;; :accent colours the chrome (cursor, prompts, matches, headings) and never
;; syntax.  Gruvbox marks the current match and the statusline's active state in
;; bright yellow (Search, IncSearch), so the chrome accent is `yellow'.
;; It shares a hue with :type, which the standard allows.

;;; Code:

(require 'reader-theme)

(reader-theme-deftheme reader-gruvbox
  "Gruvbox dark, medium (base16), on the reader standard."
  :palette ((bg "#282828")
            (bg1 "#3c3836")
            (bg2 "#504945")
            (bg3 "#665c54")
            (fg3 "#bdae93")
            (fg "#d5c4a1")
            (fg1 "#ebdbb2")
            (fg0 "#fbf1c7")
            (red "#fb4934")
            (orange "#fe8019")
            (yellow "#fabd2f")
            (green "#b8bb26")
            (aqua "#8ec07c")
            (blue "#83a598")
            (purple "#d3869b")
            (neutral-orange "#d65d0e"))
  :bg bg
  :fg fg
  :syntax red
  :callable green
  :type yellow
  :value purple
  :meta aqua
  :binding blue
  :popout orange
  :accent yellow
  :error red
  :warning yellow
  :added green)

;;; reader-gruvbox-theme.el ends here
