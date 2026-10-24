;;; reader-kanagawa-theme.el --- Kanagawa (base16), on the reader standard. -*- lexical-binding: t; -*-

;; A reader-standard theme (research/PATTERNS.md); see `themer-reader-deftheme'.
;; Edit a palette colour and re-evaluate (or use `themer-preview-mode'):
;; every tier is derived again.

;; :accent colours the chrome (cursor, prompts, matches, headings) and never
;; syntax.  Kanagawa's warm accent is its orange, `surimiOrange': the
;; palette's one warm colour that clears Lc 60 on the background (the gold
;; `boatYellow2' reaches only 52).  It shares a hue with :value.

;;; Code:

(require 'themer-reader)

(themer-reader-deftheme reader-kanagawa
  "Kanagawa (base16), on the reader standard."
  :palette ((sumiInk1 "#1f1f28")
            (sumiInk0 "#16161d")
            (waveBlue1 "#223249")
            (sumiInk4 "#54546d")
            (fujiGray "#727169")
            (fujiWhite "#dcd7ba")
            (oldWhite "#c8c093")
            (katanaGray "#717c7c")
            (autumnRed "#c34043")
            (surimiOrange "#ffa066")
            (boatYellow2 "#c0a36e")
            (autumnGreen "#76946a")
            (waveAqua1 "#6a9589")
            (crystalBlue "#7e9cd8")
            (oniViolet "#957fb8")
            (sakuraPink "#d27e99"))
  :bg sumiInk1
  :fg fujiWhite
  :syntax oniViolet
  :callable crystalBlue
  :type boatYellow2
  :value surimiOrange
  :meta autumnRed
  :binding waveAqua1
  :popout sakuraPink
  :accent surimiOrange
  :error autumnRed
  :warning boatYellow2
  :added autumnGreen)

;;; reader-kanagawa-theme.el ends here
