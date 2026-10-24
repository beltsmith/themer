;;; themer-preview.el --- Live preview for theme files -*- lexical-binding: t; -*-

;; Author: beltsmith <me@alexgirdler.com>
;; Package-Requires: ((emacs "29.1"))

;;; Commentary:
;;
;; `themer-preview-mode' in a `<name>-theme.el' buffer does two things:
;;
;;   - Re-evaluates the buffer (saved or not) shortly after each edit and
;;     re-enables the theme, so retuning a palette hex or rebinding a role
;;     shows up in every window straight away.
;;   - Paints each palette/role name with the colour it resolves to, both
;;     where it is defined in the palette and wherever a face spec uses it,
;;     so the role -> colour mapping can be read off the buffer.
;;
;; Turning the mode off removes the swatches, and disables the theme if it
;; wasn't already enabled when the mode was turned on.
;;
;; The swatches understand `autothemer-deftheme' forms, and
;; `themer-reader-deftheme' specs: each hex string, each palette entry's
;; name, and each slot that names a palette entry get the colour.  The live
;; reload works for any theme file named `<name>-theme.el', or any buffer
;; holding a `themer-reader-deftheme' form.

;;; Code:

(require 'color)

(defcustom themer-preview-delay 0.4
  "Idle seconds after an edit before the theme is re-evaluated."
  :type 'number
  :group 'themer)

(defvar-local themer-preview--timer nil)

(defvar-local themer-preview--prior-themes nil
  "`custom-enabled-themes' at the time `themer-preview-mode' was turned on.")

(defun themer-preview--theme ()
  "The theme this buffer defines.
Taken from its `<name>-theme.el' file name, else from the name in a
`themer-reader-deftheme' form."
  (or (when-let* ((file (buffer-file-name))
                  (name (file-name-nondirectory file))
                  ((string-match "\\`\\(.+\\)-theme\\.el\\'" name)))
        (intern (match-string 1 name)))
      (save-excursion
        (goto-char (point-min))
        (when (re-search-forward "^(themer-reader-deftheme[ \t\n]+\\(\\(?:\\sw\\|\\s_\\)+\\)" nil t)
          (intern (match-string-no-properties 1))))))

(defun themer-preview--sections ()
  "Bounds of the palette and face-spec lists of the `autothemer-deftheme' form.
Return ((PALETTE-BEG . PALETTE-END) . (FACES-BEG . FACES-END)), or nil."
  (save-excursion
    (goto-char (point-min))
    (when (re-search-forward "^(autothemer-deftheme\\_>" nil t)
      (ignore-errors
        (forward-sexp 2)                ; theme name, docstring
        (let* ((palette-end (scan-sexps (point) 1))
               (faces-end (scan-sexps palette-end 1)))
          (cons (cons (scan-sexps palette-end -1) palette-end)
                (cons (scan-sexps faces-end -1) faces-end)))))))

(defun themer-preview--palette (beg end)
  "Alist of (NAME . COLOUR) for the palette list between BEG and END.
Rows are resolved in order, as autothemer's `let*' does, so a role bound to
a palette name gets that name's colour.  Only the first display's colour of
each row is used, and rows that don't resolve to a colour are dropped."
  (let (env)
    ;; The car of the palette is the display list, e.g. ((t)).
    (dolist (row (cdr (read (buffer-substring-no-properties beg end))))
      (when (and (consp row) (symbolp (car row)))
        (let ((colour (ignore-errors (eval (cadr row) (or env t)))))
          (when (and (stringp colour) (color-defined-p colour))
            (push (cons (car row) colour) env)))))
    env))

(defun themer-preview--reader-bounds ()
  "Bounds (BEG . END) of the `themer-reader-deftheme' form, or nil."
  (save-excursion
    (goto-char (point-min))
    (when (re-search-forward "^(themer-reader-deftheme\\_>" nil t)
      (let ((beg (match-beginning 0)))
        (ignore-errors (cons beg (scan-sexps beg 1)))))))

(defun themer-preview--swatch (beg end colour)
  "Paint BEG..END with COLOUR as its background."
  (let ((ov (make-overlay beg end)))
    (overlay-put ov 'themer-preview t)
    (overlay-put ov 'evaporate t)
    (overlay-put ov 'face
                 `(:background ,colour
                   :foreground ,(if (color-dark-p (color-name-to-rgb colour))
                                    "white" "black")))))

(defun themer-preview--reader-palette (bounds)
  "Alist (NAME . COLOUR) of the :palette of the reader form in BOUNDS."
  (let* ((form (ignore-errors (read (buffer-substring-no-properties (car bounds) (cdr bounds)))))
         (spec (and (consp form) (nthcdr 3 form)))
         (pal (and (listp spec) (ignore-errors (plist-get spec :palette))))
         out)
    (when (listp pal)
      (dolist (e pal)
        (when (and (consp e) (symbolp (car e)) (stringp (car-safe (cdr e)))
                   (color-defined-p (cadr e)))
          (push (cons (car e) (cadr e)) out))))
    (nreverse out)))

(defun themer-preview--paint-hexes (bounds)
  "Paint every \"#rrggbb\" string inside BOUNDS with its colour.
Palette names in a reader form get their entry's colour: where the
palette defines them and wherever a slot uses them."
  (remove-overlays (point-min) (point-max) 'themer-preview t)
  (let ((palette (themer-preview--reader-palette bounds)))
    (save-excursion
      (goto-char (car bounds))
      (while (re-search-forward "\"\\(#[0-9a-fA-F]\\{6\\}\\)\"" (cdr bounds) t)
        (let ((beg (match-beginning 0)) (end (match-end 0)) (colour (match-string 1)))
          (unless (save-excursion (nth 4 (syntax-ppss beg)))  ; not in a comment
            (themer-preview--swatch beg end colour))))
      (when palette
        (goto-char (car bounds))
        (while (re-search-forward "\\_<\\(?:\\sw\\|\\s_\\)+\\_>" (cdr bounds) t)
          (when-let* ((colour (alist-get (intern-soft (match-string 0)) palette))
                      ((not (nth 8 (save-excursion (syntax-ppss (match-beginning 0)))))))
            (themer-preview--swatch (match-beginning 0) (match-end 0) colour)))))))

(defun themer-preview--paint (sections palette)
  "Paint every PALETTE name inside SECTIONS with its colour.
In the face specs the car of each list is a face name, not a role (e.g.
the `region' face vs the `region' role), so those are skipped."
  (remove-overlays (point-min) (point-max) 'themer-preview t)
  (save-excursion
    (pcase-dolist (`((,beg . ,end) . ,skip-car) `((,(car sections) . nil)
                                                 (,(cdr sections) . t)))
      (goto-char beg)
      (while (re-search-forward "\\_<\\(?:\\sw\\|\\s_\\)+\\_>" end t)
        (when-let* ((colour (alist-get (intern-soft (match-string 0)) palette))
                    ((not (nth 8 (syntax-ppss))))  ; not in a string/comment
                    ((not (and skip-car
                               (eq (char-before (match-beginning 0)) ?\()))))
          (themer-preview--swatch (match-beginning 0) (match-end 0) colour))))))

(defun themer-preview--balanced-p ()
  "Non-nil if the buffer's parens balance, i.e. it's worth evaluating."
  (condition-case nil
      (progn (scan-sexps (point-min) (point-max)) t)
    (scan-error nil)))

(defun themer-preview--apply (theme)
  "Re-evaluate the buffer as the definition of THEME, then enable THEME.
Mirrors the reload path of `load-theme'.  If evaluation fails the previous
settings are put back, so a half-typed spec doesn't strip every face."
  (let ((old (get theme 'theme-settings))
        ok)
    (disable-theme theme)
    (put theme 'theme-settings nil)
    (unwind-protect
        (progn (eval-buffer) (setq ok t))
      (unless ok (put theme 'theme-settings old))
      (when (custom-theme-p theme)
        (enable-theme theme)))))

(defun themer-preview-refresh (&optional buffer)
  "Repaint the swatches in BUFFER and re-apply the theme it defines.
BUFFER defaults to the current buffer."
  (interactive)
  (let ((buffer (or buffer (current-buffer))))
    (when (buffer-live-p buffer)
      (with-current-buffer buffer
        (when-let* ((theme (themer-preview--theme))
                    ((themer-preview--balanced-p)))
          (condition-case err
              (progn
                (if-let* ((sections (themer-preview--sections)))
                    (themer-preview--paint
                     sections (themer-preview--palette (caar sections) (cdar sections)))
                  (when-let* ((bounds (themer-preview--reader-bounds)))
                    (themer-preview--paint-hexes bounds)))
                (themer-preview--apply theme))
            (error (message "themer-preview: %s" (error-message-string err)))))))))

(defun themer-preview--schedule (&rest _)
  "Debounce `themer-preview-refresh' after a buffer change."
  (when (timerp themer-preview--timer)
    (cancel-timer themer-preview--timer))
  (setq themer-preview--timer
        (run-with-idle-timer themer-preview-delay nil
                             #'themer-preview-refresh (current-buffer))))

;;;###autoload
(define-minor-mode themer-preview-mode
  "Live-preview the theme defined in the current `<name>-theme.el' buffer.
See the commentary in themer-preview.el."
  :lighter " Preview"
  :group 'themer
  (cond
   (themer-preview-mode
    (unless (themer-preview--theme)
      (setq themer-preview-mode nil)
      (user-error "Not a <name>-theme.el or reader theme buffer"))
    (setq themer-preview--prior-themes custom-enabled-themes)
    (add-hook 'after-change-functions #'themer-preview--schedule nil t)
    (themer-preview-refresh))
   (t
    (remove-hook 'after-change-functions #'themer-preview--schedule t)
    (when (timerp themer-preview--timer)
      (cancel-timer themer-preview--timer))
    (remove-overlays (point-min) (point-max) 'themer-preview t)
    (when-let* ((theme (themer-preview--theme))
                ((not (memq theme themer-preview--prior-themes))))
      (disable-theme theme)))))

(provide 'themer-preview)

;;; themer-preview.el ends here
