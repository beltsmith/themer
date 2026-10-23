;;; themer-render.el --- Render resolved buffer faces to SVG -*- lexical-binding: t; -*-

;; Author: beltsmith <me@alexgirdler.com>
;; Package-Requires: ((emacs "29.1"))

;;; Commentary:
;;
;; Snapshot the faces Emacs actually resolved at each character -- after
;; font-lock, tree-sitter and (optionally) eglot semantic tokens -- and
;; draw them as an SVG.  Because the colours come from the live face
;; pipeline rather than a hand-tagged sample, the render shows exactly
;; what a theme does to real code, including the places where one layer
;; overrides another.
;;
;; Commands:
;;
;;   `themer-render'          Render the region (or the visible window).
;;   `themer-render-compare'  Render font-lock alone next to font-lock plus
;;                            eglot semantic tokens.  Characters whose look
;;                            the tokens changed are underlined.
;;
;; Both show the image in *themer-render*, where `w' writes the SVG out.
;;
;; Headless, for rendering without a running session:
;;
;;   emacs --batch -l themer \
;;         --eval '(load-theme (quote my-theme) t)' \
;;         -f themer-batch-render FILE OUT.svg [SETTLE-SECONDS]
;;
;; Batch mode starts eglot itself when `eglot-server-programs' has a
;; server for FILE's major mode, waits SETTLE-SECONDS (default 3) for it
;; to index, and renders the comparison; otherwise it renders font-lock
;; alone.  Set up the theme, `treesit-font-lock-level', the major mode
;; and `eglot-server-programs' with --eval or -l before -f.
;;
;; The semantic-token half reads eglot's internal `eglot--semtok-state' to
;; know when tokens have arrived; it's written against the eglot that
;; ships with Emacs 31.

;;; Code:

(require 'cl-lib)
(require 'svg)
(require 'subr-x)

(defvar eglot--semtok-state)
(defvar eglot-semantic-tokens-mode)
(declare-function eglot-semantic-tokens-mode "eglot")
(declare-function eglot-managed-p "eglot")
(declare-function eglot-server-capable "eglot")
(declare-function eglot-current-server "eglot")
(declare-function eglot-shutdown "eglot")
(declare-function eglot--guess-contact "eglot")
(declare-function eglot "eglot")

(defcustom themer-render-font-family nil
  "Font family for rendered text.  nil means the `default' face's family."
  :type '(choice (const :tag "Default face" nil) string)
  :group 'themer)

(defcustom themer-render-font-size 14
  "Font size of rendered text, in pixels."
  :type 'number
  :group 'themer)

(defcustom themer-render-char-width 0.6
  "Width of one column as a fraction of `themer-render-font-size'.
0.6 suits most monospace fonts.  Each run also carries an SVG textLength,
so text stays on the column grid even if this is slightly off."
  :type 'number
  :group 'themer)

(defcustom themer-render-line-height 1.45
  "Line height as a multiple of `themer-render-font-size'."
  :type 'number
  :group 'themer)

(defcustom themer-render-semtok-timeout 10
  "Seconds to wait for eglot semantic tokens before rendering without them."
  :type 'number
  :group 'themer)

(defcustom themer-render-diff-colour nil
  "Colour of the underline marking what semantic tokens changed.
nil means the `shadow' face's foreground."
  :type '(choice (const :tag "Shadow face" nil) color)
  :group 'themer)

;;;; Snapshot

(defun themer-render--face-list (faces)
  "Normalise the `face' property value FACES to a list of faces."
  (cond ((null faces) nil)
        ((and (consp faces) (keywordp (car faces))) (list faces))
        ((consp faces) faces)
        (t (list faces))))

(defun themer-render--lookup (faces attr)
  "Value of ATTR from the first of FACES that specifies it, or nil.
Earlier faces win, as they do in the `face' property.  Anonymous face
plists and `:inherit' are followed."
  (catch 'found
    (dolist (face (themer-render--face-list faces))
      (let ((v (cond ((and (consp face) (keywordp (car face)))
                      (let ((own (plist-get face attr)))
                        (if (memq own '(nil unspecified))
                            (themer-render--lookup (plist-get face :inherit) attr)
                          own)))
                     ((facep face) (face-attribute face attr nil t)))))
        (unless (memq v '(nil unspecified))
          (throw 'found v))))
    nil))

(defun themer-render--attrs (faces)
  "Resolve FACES to a plist of the attributes the renderer draws."
  (let ((get (lambda (attr)
               (or (themer-render--lookup faces attr)
                   (face-attribute 'default attr nil t)))))
    (list :fg (funcall get :foreground)
          :bg (funcall get :background)
          :bold (and (memq (funcall get :weight)
                           '(semi-bold bold extra-bold ultra-bold heavy black))
                     t)
          :italic (and (memq (funcall get :slant) '(italic oblique)) t)
          :underline (not (memq (themer-render--lookup faces :underline)
                                '(nil unspecified)))
          :strike (not (memq (themer-render--lookup faces :strike-through)
                             '(nil unspecified))))))

(defun themer-render--expand-tabs (text col)
  "TEXT with tabs expanded to spaces, given that TEXT starts at column COL."
  (if (not (string-search "\t" text))
      text
    (mapconcat (lambda (ch)
                 (if (eq ch ?\t)
                     (let ((n (- tab-width (% col tab-width))))
                       (setq col (+ col n))
                       (make-string n ?\s))
                   (setq col (+ col (char-width ch)))
                   (string ch)))
               text "")))

(defun themer-render--snapshot (beg end)
  "Snapshot the resolved faces of the lines between BEG and END.
Return a list of lines, each a list of runs (COLUMN TEXT ATTRS)."
  (font-lock-ensure beg end)
  (save-excursion
    (goto-char beg)
    (forward-line 0)
    (let (lines)
      (while (and (< (point) end) (not (eobp)))
        (let ((eol (line-end-position)) runs)
          (while (< (point) eol)
            (let ((next (min (next-single-property-change (point) 'face nil eol)
                             (next-single-char-property-change (point) 'invisible nil eol)))
                  (col (current-column)))
              (unless (invisible-p (point))
                (push (list col
                            (themer-render--expand-tabs
                             (buffer-substring-no-properties (point) next) col)
                            (themer-render--attrs (get-text-property (point) 'face)))
                      runs))
              (goto-char next)))
          (push (nreverse runs) lines))
        (forward-line 1))
      (nreverse lines))))

(defun themer-render--attrs-at (line col)
  "Attributes at column COL of snapshot LINE, or nil past its end."
  (catch 'found
    (pcase-dolist (`(,start ,text ,attrs) line)
      (when (and (>= col start) (< col (+ start (string-width text))))
        (throw 'found attrs)))
    nil))

;;;; SVG

(defun themer-render--width (lines)
  "Widest column in snapshot LINES."
  (let ((w 0))
    (dolist (line lines w)
      (pcase-dolist (`(,col ,text ,_) line)
        (setq w (max w (+ col (string-width text))))))))

(defun themer-render--svg (panels)
  "Draw PANELS side by side and return the SVG object.
Each panel is (TITLE LINES REF-LINES).  When REF-LINES is non-nil,
characters that look different from REF-LINES are underlined."
  (let* ((size themer-render-font-size)
         (cw (* size themer-render-char-width))
         (lh (* size themer-render-line-height))
         (pad (round (* size 1.2)))
         (head (round (* lh 2)))
         (family (or themer-render-font-family
                     (face-attribute 'default :family nil t)))
         ;; Batch frames report the family as "default"; always fall back
         ;; to a generic monospace so the column grid holds.
         (family (if (and (stringp family) (not (equal family "default")))
                     (format "'%s', monospace" family)
                   "monospace"))
         (bg (face-attribute 'default :background nil t))
         (bg (if (stringp bg) bg "black"))
         (fg (face-attribute 'default :foreground nil t))
         (shadow (or themer-render-diff-colour
                     (let ((s (face-attribute 'shadow :foreground nil t)))
                       (if (stringp s) s fg))))
         (widths (mapcar (lambda (p)
                           (round (+ (* 2 pad)
                                     (* cw (max (themer-render--width (nth 1 p))
                                                (string-width (nth 0 p)))))))
                         panels))
         (height (round (+ head pad (* lh (apply #'max 1 (mapcar (lambda (p) (length (nth 1 p)))
                                                                 panels))))))
         (gap 2)
         (svg (svg-create (+ (apply #'+ widths) (* gap (1- (length panels)))) height))
         (x0 0))
    (svg-rectangle svg 0 0 (+ (apply #'+ widths) (* gap (1- (length panels)))) height
                   :fill shadow)
    (cl-loop
     for (title lines ref) in panels
     for width in widths
     for has-ref = (and ref t)
     do
     (svg-rectangle svg x0 0 width height :fill bg)
     (svg-text svg title :x (+ x0 pad) :y (round (* lh 1.1))
               :font-family family :font-size size :font-weight "bold" :fill shadow
               :xml:space "preserve")
     (cl-loop
      for line in lines
      for ref-line = (pop ref)
      for row from 0
      for top = (+ head (* row lh))
      do
      (pcase-dolist (`(,col ,text ,attrs) line)
        (let ((x (+ x0 pad (* col cw)))
              (len (string-width text)))
          (when (and (stringp (plist-get attrs :bg))
                     (not (equal (plist-get attrs :bg) bg)))
            (svg-rectangle svg x top (* len cw) lh :fill (plist-get attrs :bg)))
          (unless (string-blank-p text)
            (svg-text svg text
                      :x x :y (+ top (* lh 0.75))
                      :textLength (* len cw) :lengthAdjust "spacing"
                      :font-family family :font-size size
                      :fill (let ((c (plist-get attrs :fg))) (if (stringp c) c fg))
                      :font-weight (if (plist-get attrs :bold) "bold" "normal")
                      :font-style (if (plist-get attrs :italic) "italic" "normal")
                      :text-decoration (string-join
                                        (delq nil (list (and (plist-get attrs :underline) "underline")
                                                        (and (plist-get attrs :strike) "line-through")))
                                        " ")
                      :xml:space "preserve"))
          ;; Underline the columns whose look differs from the reference.
          (when has-ref
            (let (run-start)
              (dotimes (i (1+ len))
                (let ((differs (and (< i len)
                                    (not (eq (aref text (min i (1- (length text)))) ?\s))
                                    (not (equal attrs (themer-render--attrs-at
                                                       ref-line (+ col i)))))))
                  (cond ((and differs (not run-start)) (setq run-start i))
                        ((and (not differs) run-start)
                         (svg-line svg (+ x (* run-start cw)) (+ top lh -2)
                                   (+ x (* i cw)) (+ top lh -2)
                                   :stroke shadow :stroke-width 2)
                         (setq run-start nil))))))))))
     (setq x0 (+ x0 width gap)))
    svg))

;;;; Display

(defvar-local themer-render--image nil
  "The SVG shown in this *themer-render* buffer.")

(defvar-keymap themer-render-mode-map
  :doc "Keymap for `themer-render-mode'."
  "w" #'themer-render-write)

(define-derived-mode themer-render-mode special-mode "Themer-Render"
  "Major mode for viewing a `themer-render' image.
\\{themer-render-mode-map}")

(defun themer-render--show (svg)
  "Show SVG in the *themer-render* buffer."
  (with-current-buffer (get-buffer-create "*themer-render*")
    (let ((inhibit-read-only t))
      (themer-render-mode)
      (erase-buffer)
      (setq themer-render--image svg)
      (if (display-images-p)
          (svg-insert-image svg)
        (insert "Images can't be displayed here; press `w' to write the SVG.\n"))
      (goto-char (point-min)))
    (pop-to-buffer (current-buffer))))

(defun themer-render--write (svg file)
  "Write SVG to FILE."
  (with-temp-file file
    (insert "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n")
    (svg-print svg)))

(defun themer-render-write (file)
  "Write the SVG shown in this buffer to FILE."
  (interactive (list (read-file-name "Write SVG to: " nil nil nil "themer-render.svg"))
               themer-render-mode)
  (unless themer-render--image
    (user-error "No render in this buffer"))
  (themer-render--write themer-render--image (expand-file-name file))
  (message "Wrote %s" file))

;;;; Commands

(defun themer-render--bounds ()
  "The active region, or else the part of the buffer visible in the window."
  (if (use-region-p)
      (list (region-beginning) (region-end))
    (list (window-start) (window-end nil t))))

(defun themer-render--semtok-capable-p ()
  "Non-nil if eglot manages this buffer with a semantic-token server."
  (and (featurep 'eglot)
       (eglot-managed-p)
       (eglot-server-capable :semanticTokensProvider)))

(defun themer-render--semtok-snapshot (beg end)
  "Snapshot BEG..END with eglot semantic tokens applied.
Waits up to `themer-render-semtok-timeout' seconds for the tokens."
  ;; Enabling the mode clears its state, so the next fontification asks
  ;; the server for a fresh set of tokens.
  (eglot-semantic-tokens-mode 1)
  (font-lock-flush beg end)
  (font-lock-ensure beg end)
  (let ((deadline (+ (float-time) themer-render-semtok-timeout)))
    (while (and (< (float-time) deadline)
                (not (plist-get eglot--semtok-state :data)))
      (accept-process-output nil 0.05)))
  (unless (plist-get eglot--semtok-state :data)
    (message "themer-render: no semantic tokens after %ss"
             themer-render-semtok-timeout))
  ;; The response flushed the requested regions; refontify them.
  (themer-render--snapshot beg end))

(defun themer-render--compare-panels (beg end)
  "Panels for font-lock alone and font-lock plus semantic tokens."
  (let ((was eglot-semantic-tokens-mode)
        plain semantic)
    (unwind-protect
        (progn
          (eglot-semantic-tokens-mode -1)
          (setq plain (themer-render--snapshot beg end)
                semantic (themer-render--semtok-snapshot beg end)))
      (eglot-semantic-tokens-mode (if was 1 -1)))
    (list (list (format "%s — font-lock" (buffer-name)) plain nil)
          (list (format "%s — + eglot semantic tokens" (buffer-name)) semantic plain))))

;;;###autoload
(defun themer-render (beg end)
  "Render the resolved faces between BEG and END as an SVG.
Interactively, render the region if active, else the visible window."
  (interactive (themer-render--bounds))
  (themer-render--show
   (themer-render--svg (list (list (buffer-name) (themer-render--snapshot beg end) nil)))))

;;;###autoload
(defun themer-render-compare (beg end)
  "Render BEG..END with and without eglot semantic tokens, side by side.
Characters whose look the semantic tokens changed are underlined.
Interactively, render the region if active, else the visible window."
  (interactive (themer-render--bounds))
  (unless (themer-render--semtok-capable-p)
    (user-error "Eglot isn't managing this buffer with a semantic-token server"))
  (themer-render--show (themer-render--svg (themer-render--compare-panels beg end))))

;;;###autoload
(defun themer-batch-render ()
  "Render a file from the command line; see the commentary for usage.
Arguments, taken from `command-line-args-left': FILE OUT.svg [SETTLE]."
  (unless noninteractive
    (user-error "`themer-batch-render' is for --batch use"))
  (let* ((file (expand-file-name (or (pop command-line-args-left)
                                     (error "Usage: -f themer-batch-render FILE OUT.svg [SETTLE]"))))
         (out (expand-file-name (or (pop command-line-args-left)
                                    (error "Missing OUT.svg"))))
         (settle (string-to-number (or (pop command-line-args-left) "3"))))
    (with-current-buffer (find-file-noselect file)
      (require 'eglot)
      ;; `eglot-ensure' defers to `post-command-hook', which never runs in
      ;; batch, so connect directly.
      (when-let* ((contact (ignore-errors (eglot--guess-contact))))
        (apply #'eglot contact)
        (let ((deadline (+ (float-time) 60)))
          (while (and (not (eglot-managed-p)) (< (float-time) deadline))
            (accept-process-output nil 0.2)))
        (let ((deadline (+ (float-time) settle)))
          (while (< (float-time) deadline)
            (accept-process-output nil 0.2))))
      (let ((panels (if (themer-render--semtok-capable-p)
                        (themer-render--compare-panels (point-min) (point-max))
                      (list (list (buffer-name)
                                  (themer-render--snapshot (point-min) (point-max))
                                  nil)))))
        (themer-render--write (themer-render--svg panels) out)
        (message "themer: wrote %s (%s)" out
                 (if (cdr panels) "font-lock vs semantic tokens" "font-lock only")))
      (when (and (featurep 'eglot) (eglot-current-server))
        (ignore-errors (eglot-shutdown (eglot-current-server)))))))

(provide 'themer-render)

;;; themer-render.el ends here
