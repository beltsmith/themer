;;; themer.el --- Tools for developing Emacs colour themes -*- lexical-binding: t; -*-

;; Author: beltsmith <me@alexgirdler.com>
;; Version: 0.1.0
;; Package-Requires: ((emacs "29.1"))
;; Keywords: faces, tools

;;; Commentary:
;;
;; A library for developing a colour theme while looking at it.  The
;; reader-theme package (reader-theme.el, in the same repository) is built
;; on it.
;;
;; `themer-preview-mode'  (themer-preview.el)
;;   In an autothemer `<name>-theme.el' buffer, re-evaluate and re-enable
;;   the theme shortly after each edit, saved or not, and paint each
;;   palette/role name with the colour it resolves to.
;;
;; `themer-render', `themer-render-compare'  (themer-render.el)
;;   Render the faces Emacs actually resolved in a buffer to an SVG.
;;   `themer-render-compare' renders font-lock alone next to font-lock
;;   plus eglot semantic tokens, and underlines what the tokens changed.
;;   `themer-batch-render' does the same headlessly from the command line.
;;
;; `themer-samples-show'  (themer-samples.el)
;;   Real buffers of code, one per language, showing a set of faces
;;   through `face-remapping-alist', without enabling a theme; with eglot
;;   semantic tokens where a server is installed.
;;
;; `themer-picker-adjust'  (themer-picker.el)
;;   Adjust the hex colour at point or in the region in OKLCH, in place,
;;   with single keys and a live swatch.
;;
;; themer-colour.el holds the colour maths: OKLab/OKLCH, CIELAB, APCA,
;; Szafir text distinguishability, gamut fitting and CVD simulation.

;;; Code:

(defgroup themer nil
  "Tools for developing colour themes."
  :group 'faces
  :prefix "themer-")

(require 'themer-preview)
(require 'themer-render)
(require 'themer-colour)
(require 'themer-picker)
(require 'themer-samples)

(provide 'themer)

;;; themer.el ends here
