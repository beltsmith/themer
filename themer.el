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

;;; Code:

(defgroup themer nil
  "Tools for developing colour themes."
  :group 'faces
  :prefix "themer-")

(require 'themer-preview)
(require 'themer-render)

(provide 'themer)

;;; themer.el ends here
