;;; reader-monokai-theme.el --- Monokai (base16), on the reader standard. -*- lexical-binding: t; -*-

;; A reader-standard theme (research/PATTERNS.md); see `themer-reader-deftheme'.
;; Edit a palette colour and re-evaluate (or use `themer-preview-mode'):
;; every tier is derived again.

;; :accent colours the chrome (cursor, prompts, matches, headings) and never
;; syntax.  Monokai Sublime highlights the find match and the caret line in yellow,
;; so the chrome accent is `yellow' (base16's #f4bf75, not the syntax
;; hues pink or green).

;;; Code:

(require 'themer-reader)

(themer-reader-deftheme reader-monokai
  "Monokai (base16), on the reader standard."
  :palette ((bg "#272822")
            (bg1 "#383830")
            (selection "#49483e")
            (comment "#75715e")
            (fg-dim "#a59f85")
            (fg "#f8f8f2")
            (fg1 "#f5f4f1")
            (fg2 "#f9f8f5")
            (pink "#f92672")
            (orange "#fd971f")
            (yellow "#f4bf75")
            (green "#a6e22e")
            (aqua "#a1efe4")
            (blue "#66d9ef")
            (purple "#ae81ff")
            (brown "#cc6633"))
  :bg bg
  :fg fg
  :syntax pink
  :callable green
  :type blue
  :value purple
  :meta orange
  :binding aqua
  :popout orange
  :accent yellow
  :error pink
  :warning yellow
  :added green)

;;; reader-monokai-theme.el ends here
