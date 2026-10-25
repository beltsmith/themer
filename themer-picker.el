;;; themer-picker.el --- Adjust a hex colour in place, in OKLCH -*- lexical-binding: t; -*-

;; Author: beltsmith <me@alexgirdler.com>
;; Package-Requires: ((emacs "29.1"))

;;; Commentary:
;;
;; `themer-picker-adjust' picks up the "#rrggbb" (or "#rgb") at point, or
;; the one in the region, and adjusts it in place with single keys, the
;; text and a swatch over it updating as you go:
;;
;;   l / L   lightness down / up        c / C   chroma down / up
;;   h / H   hue down / up              r       read a new colour
;;   RET     accept                     C-g, q  revert
;;
;; A prefix argument multiplies the step.  Any other key accepts and runs
;; as usual.  The colour is held in OKLCH, so hue survives a trip through
;; grey; out-of-gamut values are fitted, and the echo area says so.  The
;; whole adjustment is one undo step.  It works on any text, including the
;; fields of the reader theme form.

;;; Code:

(require 'color)
(require 'thingatpt)
(require 'themer-colour)

(defcustom themer-picker-steps '(0.01 0.005 2.0)
  "Steps of `themer-picker-adjust': OKLCH lightness, chroma and hue (degrees)."
  :type '(list (number :tag "Lightness") (number :tag "Chroma") (number :tag "Hue"))
  :group 'themer)

(defconst themer-picker--regexp "#\\(?:[0-9a-fA-F]\\{6\\}\\|[0-9a-fA-F]\\{3\\}\\)\\b"
  "A hex colour.")

(defvar themer-picker--state nil
  "The adjustment in progress, or nil.
A plist (:start M :end M :lch (L C H) :upcase B :overlay OV :group G).")

(defun themer-picker--bounds ()
  "Bounds (START . END) of the hex colour in the region or at point, or nil."
  (if (use-region-p)
      (let ((text (buffer-substring-no-properties (region-beginning) (region-end))))
        (when (string-match (concat "\\`[ \t]*\\(" themer-picker--regexp "\\)[ \t]*\\'") text)
          (cons (+ (region-beginning) (match-beginning 1))
                (+ (region-beginning) (match-end 1)))))
    (when (thing-at-point-looking-at themer-picker--regexp 7)
      (cons (match-beginning 0) (match-end 0)))))

(defun themer-picker--hex ()
  "The current colour of the adjustment, as written into the buffer."
  (pcase-let* ((`(,l ,c ,h) (plist-get themer-picker--state :lch))
               (hex (themer-colour-from-oklch l c h)))
    (if (plist-get themer-picker--state :upcase) (upcase hex) hex)))

(defun themer-picker--show ()
  "Write the current colour into the buffer, swatch it and describe it."
  (let* ((s themer-picker--state)
         (start (plist-get s :start))
         (end (plist-get s :end))
         (hex (themer-picker--hex))
         (got (themer-colour-oklch hex)))
    (with-current-buffer (marker-buffer start)
      (unless (equal hex (buffer-substring-no-properties start end))
        (save-excursion
          (goto-char start)
          (insert hex)
          (delete-region (point) end)))
      (move-overlay (plist-get s :overlay) start end)
      (overlay-put (plist-get s :overlay) 'face
                   `(:background ,hex
                     :foreground ,(if (themer-colour-dark-p hex) "white" "black"))))
    (pcase-let ((`(,l ,c ,h) (plist-get s :lch)))
      (message "%s %s  L %.3f  C %.3f%s  H %.0f   %s"
               (propertize "    " 'face `(:background ,hex)) hex l c
               (if (> (- c (nth 1 got)) 0.002) (format " (gamut %.3f)" (nth 1 got)) "")
               h
               (propertize "l/L c/C h/H r  RET accept  C-g revert" 'face 'shadow)))))

(defun themer-picker--step (index sign n)
  "Move OKLCH coordinate INDEX by SIGN times N steps, and show the result."
  (let* ((lch (copy-sequence (plist-get themer-picker--state :lch)))
         (v (+ (nth index lch) (* sign (prefix-numeric-value n) (nth index themer-picker-steps)))))
    (setf (nth index lch) (pcase index
                            (0 (min 1.0 (max 0.0 v)))
                            (1 (min 0.4 (max 0.0 v)))
                            (_ (mod v 360.0))))
    (plist-put themer-picker--state :lch lch)
    (themer-picker--show)))

(defun themer-picker-lighter (n)
  "Raise lightness by N steps."
  (interactive "p")
  (themer-picker--step 0 1 n))

(defun themer-picker-darker (n)
  "Lower lightness by N steps."
  (interactive "p")
  (themer-picker--step 0 -1 n))

(defun themer-picker-more-chroma (n)
  "Raise chroma by N steps."
  (interactive "p")
  (themer-picker--step 1 1 n))

(defun themer-picker-less-chroma (n)
  "Lower chroma by N steps."
  (interactive "p")
  (themer-picker--step 1 -1 n))

(defun themer-picker-hue-up (n)
  "Turn hue up by N steps."
  (interactive "p")
  (themer-picker--step 2 1 n))

(defun themer-picker-hue-down (n)
  "Turn hue down by N steps."
  (interactive "p")
  (themer-picker--step 2 -1 n))

(defun themer-picker-read ()
  "Replace the colour with one read by `read-color'."
  (interactive)
  (let* ((c (read-color "Colour (name or #rrggbb): "))
         (hex (cond ((themer-colour-hex-p c) c)
                    ((color-defined-p c)
                     (apply #'color-rgb-to-hex (append (color-name-to-rgb c) '(2))))
                    (t (user-error "Unknown colour %s" c)))))
    (plist-put themer-picker--state :lch (themer-colour-oklch (themer-colour-norm hex)))
    (themer-picker--show)))

(defun themer-picker-accept ()
  "Keep the adjusted colour."
  (interactive)
  (themer-picker--finish t))

(defun themer-picker-revert ()
  "Put the original colour back."
  (interactive)
  (themer-picker--finish nil))

(defvar-keymap themer-picker-map
  :doc "Keys while `themer-picker-adjust' runs."
  "l" #'themer-picker-darker
  "L" #'themer-picker-lighter
  "c" #'themer-picker-less-chroma
  "C" #'themer-picker-more-chroma
  "h" #'themer-picker-hue-down
  "H" #'themer-picker-hue-up
  "r" #'themer-picker-read
  "RET" #'themer-picker-accept
  "q" #'themer-picker-revert
  "C-g" #'themer-picker-revert
  "C-u" #'universal-argument
  "0" #'digit-argument "1" #'digit-argument "2" #'digit-argument
  "3" #'digit-argument "4" #'digit-argument "5" #'digit-argument
  "6" #'digit-argument "7" #'digit-argument "8" #'digit-argument
  "9" #'digit-argument "-" #'negative-argument)

(defvar themer-picker--exit nil "The function that ends the transient map.")

(defun themer-picker--finish (keep)
  "End the adjustment, keeping the colour if KEEP, else restoring the original."
  (when-let* ((s themer-picker--state))
    (setq themer-picker--state nil)
    (when themer-picker--exit (funcall (prog1 themer-picker--exit (setq themer-picker--exit nil))))
    (delete-overlay (plist-get s :overlay))
    (let ((buf (marker-buffer (plist-get s :start)))
          (group (plist-get s :group)))
      (when (buffer-live-p buf)
        (with-current-buffer buf
          (if keep
              (progn (accept-change-group group) (undo-amalgamate-change-group group))
            (cancel-change-group group))))
      (set-marker (plist-get s :start) nil)
      (set-marker (plist-get s :end) nil)
      (message "%s" (if keep "Colour kept" "Colour reverted")))))

;;;###autoload
(defun themer-picker-adjust ()
  "Adjust the hex colour at point or in the region, in OKLCH, in place.
\\<themer-picker-map>
  \\[themer-picker-darker] / \\[themer-picker-lighter]  lightness
  \\[themer-picker-less-chroma] / \\[themer-picker-more-chroma]  chroma
  \\[themer-picker-hue-down] / \\[themer-picker-hue-up]  hue
  \\[themer-picker-read]      read a colour
  \\[themer-picker-accept]    accept
  \\[themer-picker-revert]    revert

A prefix argument multiplies a step; any other key accepts.  Steps
are `themer-picker-steps'."
  (interactive)
  (barf-if-buffer-read-only)
  (themer-picker--finish t)
  (let* ((b (or (themer-picker--bounds) (user-error "No hex colour at point")))
         (text (buffer-substring-no-properties (car b) (cdr b)))
         (start (copy-marker (car b)))
         (end (copy-marker (cdr b) t))
         (ov (make-overlay (car b) (cdr b) nil t nil)))
    (deactivate-mark)
    (overlay-put ov 'priority 100)
    (setq themer-picker--state
          (list :start start :end end :overlay ov
                :lch (themer-colour-oklch (themer-colour-norm text))
                :upcase (let ((case-fold-search nil))
                          (and (string-match-p "[A-F]" text) (not (string-match-p "[a-f]" text))))
                :group (prepare-change-group)))
    (activate-change-group (plist-get themer-picker--state :group))
    (themer-picker--show)
    (setq themer-picker--exit
          (set-transient-map themer-picker-map
                             (lambda () (and themer-picker--state
                                             (where-is-internal this-command (list themer-picker-map) t)))
                             (lambda () (setq themer-picker--exit nil) (themer-picker--finish t))))))

(provide 'themer-picker)

;;; themer-picker.el ends here
