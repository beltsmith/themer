;;; themer.el --- Tools for developing Emacs colour themes -*- lexical-binding: t; -*-

;; Author: beltsmith <me@alexgirdler.com>
;; Version: 0.1.0
;; Package-Requires: ((emacs "29.1"))
;; Keywords: faces, tools

;;; Commentary:
;;
;; Tools for developing a colour theme while looking at it:
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
;; `themer-reader-deftheme'  (themer-reader.el)
;;   Themes on the reader colouring standard (research/PATTERNS.md): give
;;   a background, a foreground and one accent per kind family, and every
;;   salience tier is derived, checked for conformance and mapped onto
;;   faces.  `themer-reader-check' shows the conformance report,
;;   `themer-reader-export' writes a standalone theme, and
;;   `themer-reader-treesit-mode' adds tree-sitter rules for exits, type
;;   definitions, decorators, module-level bindings, constant definitions
;;   and TODO markers.
;;
;; `themer-reader-new-theme', `themer-reader-edit-theme'  (themer-reader-form.el)
;;   A form for creating and editing reader themes, with live swatches,
;;   derived tiers, a fontified sample and the conformance checks.
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
(require 'themer-reader)
(require 'themer-reader-form)
(require 'themer-picker)

(provide 'themer)

;;; themer.el ends here
