;;; reader-blush-theme.el --- Blush, on the reader standard. -*- lexical-binding: t; -*-

;; A reader-standard theme (research/PATTERNS.md); see `reader-theme-deftheme'.
;; Edit a palette colour and re-evaluate (or use `themer-preview-mode'):
;; every tier is derived again.

;; :accent colours the chrome (cursor, prompts, matches, headings) and never
;; syntax.  Blue, purple and orange match the others' OKLCH lightness and
;; chroma.  :binding is a pale pink hex outside the palette, a quiet tint
;; on parameters.

;;; Code:

(require 'reader-theme)

(reader-theme-deftheme reader-blush
  "Blush, on the reader standard."
  :palette ((bg "#1c1d21")
            (fg "#dddfe4")
            (red "#f8667b")
            (yellow "#ceb300")
            (green "#80f3ca")
            (blue "#95d6ff")
            (purple "#978bf2")
            (orange "#ffc0a5")
            (accent "#fea2b6"))
  :bg bg
  :fg fg
  :syntax red
  :callable blue
  :value purple
  :type yellow
  :meta green
  :popout orange
  :accent accent
  :error red
  :warning yellow
  :added green
  :binding "#febdf1")

;;; reader-blush-theme.el ends here
