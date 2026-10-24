;;; reader-zenburn-theme.el --- Zenburn (base16), on the reader standard. -*- lexical-binding: t; -*-

;; A reader-standard theme (research/PATTERNS.md); see `themer-reader-deftheme'.
;; Edit a palette colour and re-evaluate (or use `themer-preview-mode'):
;; every tier is derived again.

;; :accent colours the chrome (cursor, prompts, matches, headings) and never
;; syntax.  Zenburn's own theme draws the minibuffer prompt and buffer name in its
;; light yellow, so the chrome accent is `yellow-1'.  It shares a hue with
;; :syntax.

;;; Code:

(require 'themer-reader)

(themer-reader-deftheme reader-zenburn
  "Zenburn (base16), on the reader standard."
  :palette ((bg "#383838")
            (bg1 "#404040")
            (bg2 "#606060")
            (bg3 "#6f6f6f")
            (grey "#808080")
            (fg "#dcdccc")
            (silver "#c0c0c0")
            (white "#ffffff")
            (red+1 "#dca3a3")
            (orange "#dfaf8f")
            (yellow-1 "#e0cf9f")
            (green-2 "#5f7f5f")
            (cyan "#93e0e3")
            (blue-1 "#7cb8bb")
            (magenta "#dc8cc3")
            (black "#000000"))
  :bg bg
  :fg fg
  :syntax yellow-1
  :callable cyan
  :type blue-1
  :value red+1
  :meta orange
  :binding green-2
  :popout magenta
  :accent yellow-1
  :error red+1
  :warning yellow-1
  :added green-2)

;;; reader-zenburn-theme.el ends here
