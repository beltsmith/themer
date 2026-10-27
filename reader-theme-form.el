;;; reader-theme-form.el --- A form for creating and editing reader themes -*- lexical-binding: t; -*-

;; Author: beltsmith <me@alexgirdler.com>
;; Package-Requires: ((emacs "29.1"))

;;; Commentary:
;;
;; A customize-like form (widget.el) for reader themes:
;;
;;   `reader-theme-new'   open an empty form, or one seeded from a theme
;;   `reader-theme-edit'  open the form on a reader theme file
;;
;; The palette comes first: one row per named colour, with its name, hex,
;; a swatch on the theme's background, its hue and Lc, and the slots that
;; use it.  Each slot then names a palette entry or holds a raw hex, with a
;; swatch, a "Pick" button (a menu of the palette entries, a custom hex, or
;; a new entry) and a short status from the conformance result.  Below them
;; are the derived tiers and the conformance checks.  The code samples
;; (TypeScript, Python, Rust, C, Go, Emacs Lisp; a checkbox each) are real
;; buffers beside the form, `*reader-theme-sample: NAME (LANGUAGE)*',
;; showing the derived faces.  Edits re-derive after
;; `themer-preview-delay' idle seconds, only when a colour changed.  "Apply"
;; enables the theme globally until it is toggled off or the form is killed.
;;
;; Keys: TAB and S-TAB move between fields, C-c C-c saves, C-c C-k cancels,
;; C-c C-a adjusts the hex in the field (`themer-picker-adjust').

;;; Code:

(require 'cl-lib)
(require 'subr-x)
(require 'wid-edit)
(require 'color)
(require 'themer-colour)
(require 'reader-theme)
(require 'themer-picker)
(require 'themer-samples)
(require 'themer-render)

(defvar themer-preview-delay)
(declare-function custom-theme--load-path "custom")

;;;; Model
;;
;; A model is a plist (:name SYMBOL :doc STRING :spec PLIST :file FILE
;; :prefix STRING :suffix STRING :orig (NAME . DOC) :form STRING
;; :orig-spec PLIST).  :prefix and :suffix are the file text around the
;; `reader-theme-deftheme' form, kept as is when saving; :form is the
;; form's own text, kept while the name, doc and spec are unchanged.
;;
;; The form's fields are read into a state, a plist (:name STRING :doc
;; STRING :palette ((NAME HEX)...) :slots ((KEY . TEXT)...)) of the texts
;; as typed.  The palette operations (add, rename, delete) work on states.

(defconst reader-theme-form--fields
  '((:bg "Background" base t "")
    (:fg "Foreground" base t "variables, operators")
    (:syntax "Syntax" family t "keywords; exits bold")
    (:callable "Callable" family t "calls; definitions bold")
    (:type "Type" family nil "types, modules; definitions bold")
    (:value "Value" family t "strings; numbers, constants")
    (:meta "Meta" family nil "macros; decorators, attributes")
    (:binding "Binding" cue nil "parameter tint")
    (:popout "Popout" cue nil "TODO markers")
    (:accent "Accent" ui nil "cursor, prompts, matches")
    (:error "Error" convention nil "")
    (:warning "Warning" convention nil "")
    (:added "Added" convention nil "")
    (:removed "Removed" convention nil ""))
  "Colour fields: (KEY LABEL SECTION REQUIRED NOTE), in spec order.")

(defun reader-theme-form--keys ()
  "The colour keys in spec order."
  (mapcar #'car reader-theme-form--fields))

(defconst reader-theme-form--custom "Custom hex…"
  "The Pick menu entry for a colour not in the palette.")

(defconst reader-theme-form--add "Add to palette…"
  "The Pick menu entry for a new palette entry.")

(defun reader-theme-form--deftheme-bounds ()
  "Bounds (BEG . END) of the `reader-theme-deftheme' form in this buffer."
  (save-excursion
    (goto-char (point-min))
    (when (re-search-forward "^(reader-theme-deftheme\\_>" nil t)
      (let ((beg (match-beginning 0)))
        (with-syntax-table emacs-lisp-mode-syntax-table
          (cons beg (scan-sexps beg 1)))))))

(defun reader-theme-form-parse (text &optional file)
  "The form model of theme source TEXT, from FILE if given."
  (with-temp-buffer
    (insert text)
    (let* ((bounds (or (reader-theme-form--deftheme-bounds)
                       (user-error "No reader-theme-deftheme form%s"
                                   (if file (format " in %s" file) ""))))
           (text (buffer-substring-no-properties (car bounds) (cdr bounds)))
           (form (read text))
           (doc (nth 2 form))
           (spec (reader-theme--form-spec form)))
      (list :name (nth 1 form) :doc doc
            :spec spec
            :file file
            :prefix (buffer-substring-no-properties (point-min) (car bounds))
            :suffix (buffer-substring-no-properties (cdr bounds) (point-max))
            :orig (cons (nth 1 form) doc)
            :form text :orig-spec spec))))

(defun reader-theme-form-read-file (file)
  "The form model of reader theme FILE."
  (with-temp-buffer
    (insert-file-contents file)
    (reader-theme-form-parse (buffer-string) (expand-file-name file))))

(defun reader-theme-form--retitle (text model)
  "TEXT, around a deftheme form, with MODEL's original name and doc updated."
  (pcase-let ((`(,oname . ,odoc) (plist-get model :orig))
              (name (plist-get model :name)) (doc (plist-get model :doc)))
    (unless (eq oname name)
      (setq text (string-replace (format "%s-theme.el" oname) (format "%s-theme.el" name) text)))
    (when (and odoc (not (equal odoc doc))
               (string-match (format "\\`;;; [^ \n]+ --- \\(%s\\)" (regexp-quote odoc)) text))
      (setq text (replace-match doc t t text 1)))
    text))

(defun reader-theme-form-source (model)
  "Theme file source for MODEL.
The deftheme form is written out again unless MODEL's name, doc and spec
are those it was read with."
  (let ((name (plist-get model :name)) (doc (plist-get model :doc))
        (spec (plist-get model :spec)))
    (if (plist-get model :prefix)
        (concat (reader-theme-form--retitle (plist-get model :prefix) model)
                (if (and (plist-get model :form)
                         (equal (plist-get model :orig) (cons name doc))
                         (equal (plist-get model :orig-spec) spec))
                    (plist-get model :form)
                  (reader-theme--deftheme-source name doc spec))
                (reader-theme-form--retitle (plist-get model :suffix) model))
      (reader-theme--theme-source name doc spec))))

(defun reader-theme-form--merge-spec (old values)
  "Spec of VALUES (a plist; nil values dropped), keys in the order of spec OLD.
Keys OLD lacks follow in the canonical order; a new :palette goes first."
  (let (out)
    (cl-loop for (k _) on old by #'cddr
             when (plist-get values k) do (setq out (plist-put out k (plist-get values k))))
    (dolist (k (reader-theme-form--keys))
      (when (and (plist-get values k) (not (plist-member out k)))
        (setq out (plist-put out k (plist-get values k)))))
    (when (and (plist-get values :palette) (not (plist-member out :palette)))
      (setq out (append (list :palette (plist-get values :palette)) out)))
    out))

(defun reader-theme-form--default-file (model)
  "Where MODEL is saved: its file's directory, else the theme directory."
  (expand-file-name (format "%s-theme.el" (plist-get model :name))
                    (if-let* ((f (plist-get model :file))) (file-name-directory f)
                      reader-theme-directory)))

(defun reader-theme-form-write (model &optional file)
  "Write MODEL to FILE (default `reader-theme-form--default-file').
Return MODEL updated as read back from the file."
  (reader-theme--check-spec (plist-get model :spec))
  (let ((file (expand-file-name (or file (reader-theme-form--default-file model)))))
    (make-directory (file-name-directory file) t)
    (let ((coding-system-for-write 'utf-8))
      (write-region (reader-theme-form-source model) nil file nil 'silent))
    (reader-theme-form-read-file file)))

;;;; Finding themes

(defun reader-theme-form--theme-files ()
  "Alist (NAME . FILE) of reader themes on `custom-theme-load-path'.
`reader-theme-directory' is searched too."
  (let (out)
    (dolist (dir (delete-dups (append (custom-theme--load-path)
                                      (list (expand-file-name reader-theme-directory)))))
      (when (file-directory-p dir)
        (dolist (f (directory-files dir t "-theme\\.el\\'"))
          (let ((name (string-remove-suffix "-theme.el" (file-name-nondirectory f))))
            (unless (assoc name out)
              (with-temp-buffer
                (insert-file-contents f nil 0 20000)
                (when (re-search-forward "^(reader-theme-deftheme\\_>" nil t)
                  (push (cons name f) out))))))))
    (nreverse out)))

(defun reader-theme-form--read-theme-file (prompt)
  "Read a reader theme with PROMPT: a name from the found themes, or a file."
  (let* ((themes (reader-theme-form--theme-files))
         (choice (completing-read prompt themes nil nil)))
    (cond ((string-empty-p choice) nil)   ; before `file-exists-p': "" is the cwd
          ((assoc choice themes) (cdr (assoc choice themes)))
          ((file-regular-p choice) (expand-file-name choice))
          (t (user-error "No reader theme %s" choice)))))

;;;; Colours

(defun reader-theme-form--to-hex (colour)
  "COLOUR (a name or hex) as \"#rrggbb\", or nil."
  (cond ((themer-colour-hex-p colour) (downcase colour))
        ((and (stringp colour) (color-defined-p colour))
         (apply #'color-rgb-to-hex (append (color-name-to-rgb colour) '(2))))))

(defun reader-theme-form--hue (hex)
  "Hue name of HEX, as a string."
  (symbol-name (themer-colour-hue-name hex)))

;;;; States and the palette (non-interactive)

(defun reader-theme-form--text (value)
  "Field text for spec VALUE: a hex, a palette name, or \"\"."
  (cond ((null value) "")
        ((symbolp value) (symbol-name value))
        (t value)))

(defun reader-theme-form-model-state (model)
  "The form state of MODEL: its fields as texts."
  (let ((spec (plist-get model :spec)))
    (list :name (if (plist-get model :name) (symbol-name (plist-get model :name)) "")
          :doc (or (plist-get model :doc) "")
          :palette (mapcar (lambda (e) (list (symbol-name (car e)) (cadr e)))
                           (plist-get spec :palette))
          :slots (mapcar (lambda (k) (cons k (reader-theme-form--text (plist-get spec k))))
                         (reader-theme-form--keys)))))

(defun reader-theme-form-name-ok (text)
  "Non-nil if TEXT can name a palette entry.
A letter or _ then letters, digits and _+*/<>=!?$%&~^-, but not t or nil."
  (and (stringp text)
       (let ((case-fold-search nil))
         (string-match-p "\\`[[:alpha:]_][[:alnum:]_+*/<>=!?$%&~^-]*\\'" text))
       (not (member text '("t" "nil")))))

(defun reader-theme-form-palette-check (palette)
  "Each row of PALETTE, a list of (NAME-TEXT HEX-TEXT), as (NAME HEX PROBLEM).
NAME is a symbol, or nil if the text can't name an entry; HEX a lower-case
hex or nil; PROBLEM nil, or a string saying what is wrong with the row."
  (let (seen)
    (mapcar (pcase-lambda (`(,name ,hex))
              (let* ((ok (reader-theme-form-name-ok name))
                     (dup (and ok (member name seen)))
                     (hexp (themer-colour-hex-p hex)))
                (push name seen)
                (list (and ok (intern name)) (and hexp (downcase hex))
                      (cond ((string-empty-p name) "needs a name")
                            ((not ok) "not a usable name")
                            (dup "name used twice")
                            ((not hexp) "not a #rrggbb colour")))))
            palette)))

(defun reader-theme-form-state-palette (state)
  "Alist (NAME . HEX) of the usable palette entries of STATE."
  (cl-loop for (name hex problem) in (reader-theme-form-palette-check (plist-get state :palette))
           unless problem collect (cons name hex)))

(defun reader-theme-form-state-values (state)
  "Plist KEY -> value of STATE's slots, or :bad.
A value is a lower-case hex, a palette name (a symbol), or nil when empty."
  (let ((names (mapcar #'car (reader-theme-form-palette-check (plist-get state :palette)))))
    (cl-loop for k in (reader-theme-form--keys)
             for v = (string-trim (or (alist-get k (plist-get state :slots)) ""))
             append (list k (cond ((string-empty-p v) nil)
                                  ((themer-colour-hex-p v) (downcase v))
                                  ((and (reader-theme-form-name-ok v) (memq (intern v) names))
                                   (intern v))
                                  (t :bad))))))

(defun reader-theme-form-state-resolved (state)
  "Plist KEY -> hex of STATE's slots, palette names resolved; nil or :bad."
  (let ((pal (reader-theme-form-state-palette state)))
    (cl-loop for (k v) on (reader-theme-form-state-values state) by #'cddr
             append (list k (if (and v (symbolp v) (not (eq v :bad)))
                                (or (cdr (assq v pal)) :bad)
                              v)))))

(defun reader-theme-form-palette-users (state name)
  "The slot keys of STATE whose field names palette entry NAME (a string)."
  (when (reader-theme-form-name-ok name)
    (cl-loop for (k . v) in (plist-get state :slots)
             when (equal (string-trim v) name) collect k)))

(defun reader-theme-form--state-put (state key value)
  "A copy of STATE with KEY set to VALUE."
  (plist-put (copy-sequence state) key value))

(defun reader-theme-form-set-slot (state key text)
  "A copy of STATE with slot KEY's field set to TEXT."
  (reader-theme-form--state-put
   state :slots (mapcar (lambda (s) (if (eq (car s) key) (cons key text) s))
                        (plist-get state :slots))))

(defun reader-theme-form--check-new-name (state name)
  "Signal a `user-error' unless NAME can name a new entry of STATE."
  (unless (reader-theme-form-name-ok name)
    (user-error "%S can't name a palette entry" name))
  (when (assoc name (plist-get state :palette))
    (user-error "The palette already has %s" name)))

(defun reader-theme-form-palette-add (state name hex)
  "A copy of STATE with palette entry NAME, colour HEX, added at the end."
  (reader-theme-form--check-new-name state name)
  (unless (themer-colour-hex-p hex) (user-error "%S is not a #rrggbb colour" hex))
  (reader-theme-form--state-put state :palette
                                 (append (plist-get state :palette) (list (list name (downcase hex))))))

(defun reader-theme-form-palette-rename (state old new)
  "A copy of STATE with palette entry OLD renamed NEW, in every slot too."
  (unless (assoc old (plist-get state :palette)) (user-error "No palette entry %s" old))
  (reader-theme-form--check-new-name state new)
  (let ((users (reader-theme-form-palette-users state old)))
    (reader-theme-form--state-put
     (reader-theme-form--state-put
      state :palette (mapcar (lambda (e) (if (equal (car e) old) (cons new (cdr e)) e))
                             (plist-get state :palette)))
     :slots (mapcar (lambda (s) (if (memq (car s) users) (cons (car s) new) s))
                    (plist-get state :slots)))))

(defun reader-theme-form-palette-delete (state which &optional inline)
  "A copy of STATE without palette entry WHICH: a name, or a row index.
If a slot uses the entry, signal a `user-error', unless INLINE is
non-nil: then those slots take the entry's hex."
  (let* ((pal (plist-get state :palette))
         (index (if (integerp which) which
                  (or (cl-position which pal :key #'car :test #'equal)
                      (user-error "No palette entry %s" which))))
         (row (or (nth index pal) (user-error "No palette row %s" which)))
         (rest (append (seq-take pal index) (nthcdr (1+ index) pal)))
         (users (unless (assoc (car row) rest)  ; another row has the name
                  (reader-theme-form-palette-users state (car row)))))
    (when (and users (not inline))
      (user-error "%s is used by %s" (car row)
                  (mapconcat (lambda (k) (substring (symbol-name k) 1)) users ", ")))
    (reader-theme-form--state-put
     (reader-theme-form--state-put state :palette rest)
     :slots (mapcar (lambda (s) (if (memq (car s) users) (cons (car s) (cadr row)) s))
                    (plist-get state :slots)))))

(defun reader-theme-form-suggest-name (state hex)
  "A palette name for HEX not yet in STATE: its hue name, numbered if taken."
  (let* ((base (reader-theme-form--hue hex)) (name base) (i 1))
    (while (assoc name (plist-get state :palette))
      (setq i (1+ i) name (format "%s%d" base i)))
    name))

(defun reader-theme-form-pick-candidates (palette)
  "The Pick menu for PALETTE, an alist (NAME . HEX): an alist (TEXT . ACTION).
ACTION is the palette name (a symbol), `custom' or `add'."
  (append (mapcar (lambda (e) (cons (symbol-name (car e)) (car e))) palette)
          (list (cons reader-theme-form--custom 'custom)
                (cons reader-theme-form--add 'add))))

(defun reader-theme-form--pick-annotation (palette)
  "A completion annotation function for the Pick menu of PALETTE."
  (lambda (text)
    (if-let* ((hex (cdr (assoc text (mapcar (lambda (e) (cons (symbol-name (car e)) (cdr e))) palette)))))
        (concat "  " (propertize "    " 'face `(:background ,hex)) " " hex
                " " (propertize (reader-theme-form--hue hex) 'face 'shadow))
      "")))

(defun reader-theme-form-base16-state (state slots choices)
  "A copy of STATE with the base16 SLOTS as its palette, and CHOICES applied.
SLOTS is an alist (SLOT . HEX); CHOICES an alist KEY -> slot name, or nil
to empty the field.  Palette entries of STATE that slots not in CHOICES
still use are kept after the base16 ones."
  (let* ((state (cl-loop with st = state
                         for (k . slot) in choices
                         do (setq st (reader-theme-form-set-slot st k (or slot "")))
                         finally return st))
         (kept (cl-remove-if-not
                (lambda (e) (and (not (assoc (car e) slots))
                                 (reader-theme-form-palette-users state (car e))))
                (plist-get state :palette))))
    (reader-theme-form--state-put
     state :palette (append (mapcar (lambda (s) (list (car s) (cdr s))) slots) kept))))

;;;; Statuses (non-interactive)

(defun reader-theme-form--lc (hex bg)
  "APCA Lc of HEX on BG."
  (themer-colour-alc hex bg))

(defun reader-theme-form-statuses (derived)
  "Alist KEY -> list of (SEVERITY . TEXT) for DERIVED's spec.
SEVERITY is `ok', `must' or `should'."
  (let* ((spec (plist-get derived :spec))
         (conf (plist-get derived :conformance))
         (tiers (plist-get derived :tiers))
         (bg (plist-get tiers :bg)) (fg (plist-get tiers :fg))
         (loud (plist-get tiers :loud))
         (out nil)
         (add (lambda (k sev text) (push (cons sev text) (alist-get k out)))))
    (dolist (c (plist-get conf :checks))
      (let* ((id (symbol-name (plist-get c :id)))
             (sev (if (eq (plist-get c :keyword) 'MUST) 'must 'should)))
        (unless (plist-get c :ok)
          (cond
           ((equal id "default-lc")
            (funcall add :fg sev (format "fails Lc 45 (Lc %.1f)" (reader-theme-form--lc fg bg))))
           ((equal id "default-target")
            (funcall add :fg sev (format "Lc %.1f, below 60" (reader-theme-form--lc fg bg))))
           ((member id '("dim" "dim-target" "faded-lc" "faded-target"))
            (funcall add :fg sev (format "%s tier off target" (car (split-string id "-")))))
           ((equal id "recessive") (funcall add :syntax sev "no recessive keyword tint"))
           ((string-match "\\`quiet-\\(.+\\)" id)
            (progn
              (funcall add (intern (concat ":" (match-string 1 id))) sev
                       (format "quiet tint: %s"
                               (replace-regexp-in-string
                                "another quiet colour" "another quiet tint"
                                (or (cadr (split-string (plist-get c :detail) ": ")) "none"))))))
           ((string-match "\\`loud-chroma-\\(.+\\)" id)
            (let ((hex (alist-get (intern (match-string 1 id)) loud)))
              (funcall add (intern (concat ":" (match-string 1 id))) sev
                       (format "chroma %.3f < 0.08" (nth 1 (themer-colour-oklch hex))))))
           ((string-match "\\`loud-target-\\(.+\\)" id)
            (let ((hex (alist-get (intern (match-string 1 id)) loud)))
              (funcall add (intern (concat ":" (match-string 1 id))) sev
                       (format "Lc %.1f, below 45" (reader-theme-form--lc hex bg)))))
           ((string-match "\\`loud-\\(.+\\)" id)
            (let ((hex (alist-get (intern (match-string 1 id)) loud)))
              (funcall add (intern (concat ":" (match-string 1 id))) sev
                       (format "fails Lc 35 (Lc %.1f)" (reader-theme-form--lc hex bg)))))
           ((string-match "\\`\\(distinct\\|cvd\\)-\\([a-z]+\\)-\\([a-z]+\\)\\'" id)
            (let ((a (match-string 2 id)) (b (match-string 3 id))
                  (what (if (equal (match-string 1 id) "cvd") "CVD-confusable with %s"
                          "not distinct from %s")))
              (funcall add (intern (concat ":" a)) sev (format what b))
              (funcall add (intern (concat ":" b)) sev (format what a))))
           ((equal id "binding")
            (funcall add :binding sev
                     (replace-regexp-in-string "\\`parameter tint " "" (plist-get c :detail))))
           ((equal id "binding-hue") (funcall add :binding sev "hue close to a quiet cue"))
           ((equal id "popout") (funcall add :popout sev "shares a family hue"))
           ((equal id "accent-lc")
            (funcall add :accent sev (format "Lc %.1f, below 60" (reader-theme-form--lc (plist-get tiers :accent) bg))))
           ((equal id "accent-isearch")
            (funcall add :accent sev (format "isearch text on it: Lc %.1f, below 60"
                                             (abs (reader-theme-form--lc bg (plist-get tiers :accent))))))
           ((string-match "\\`\\(error\\|warning\\|added\\|removed\\)-" id)
            (let ((k (intern (concat ":" (match-string 1 id)))))
              (funcall add k sev (format "is %s" (reader-theme-form--hue (plist-get tiers k))))))))))
    ;; Shed families, and the Lc of the ones kept.
    (dolist (fam reader-theme-families)
      (let ((k (intern (format ":%s" fam))))
        (when (plist-get spec k)
          (if-let* ((hex (alist-get fam loud)))
              (unless (alist-get k out)
                (funcall add k 'ok (format "Lc %.1f" (reader-theme-form--lc hex bg))))
            (funcall add k 'should
                     (format "shed at %s: drawn as %s" (plist-get conf :level)
                             (car (alist-get fam reader-theme--fallbacks))))))))
    (unless (alist-get :fg out)
      (funcall add :fg 'ok (format "Lc %.1f" (reader-theme-form--lc fg bg))))
    (funcall add :bg 'ok (if (themer-colour-dark-p bg) "dark" "light"))
    (when (and (plist-get spec :binding) (not (alist-get :binding out)))
      (funcall add :binding 'ok (format "tint %s" (plist-get tiers :binding))))
    (when (and (plist-get spec :accent) (not (alist-get :accent out)))
      (funcall add :accent 'ok (format "Lc %.1f" (reader-theme-form--lc (plist-get tiers :accent) bg))))
    (dolist (k '(:popout :error :warning :added :removed))
      (when (and (plist-get spec k) (not (alist-get k out)))
        (funcall add k 'ok (reader-theme-form--hue (plist-get tiers k)))))
    (mapcar (lambda (x) (cons (car x) (reverse (cdr x)))) out)))

;;;; Samples
;;
;; The samples (themer-samples.el) show the derived faces, with the reader
;; rules installed in each buffer.

(defvar-local reader-theme-form--derived nil "The last derivation shown.")
(defvar-local reader-theme-form--model nil "The model the form was opened on.")

(defun reader-theme-form--samples-title (name)
  "The samples' title for the theme called NAME."
  (format "reader-theme-sample: %s" (or name "new")))

;;;; The form buffer

(defvar-local reader-theme-form--widgets nil "Alist KEY -> field widget.")
(defvar-local reader-theme-form--overlays nil "Alist KEY -> swatch/status overlay.")
(defvar-local reader-theme-form--palette-rows nil
  "The palette rows in order, each a plist (:name WIDGET :hex WIDGET :overlay OV).
The name widget's :themer-name is the name the slots know the entry by.")
(defvar-local reader-theme-form--dynamic nil "Marker where the derived sections start.")
(defvar-local reader-theme-form--timer nil)
(defvar-local reader-theme-form--apply-widget nil)
(defvar-local reader-theme-form--samples-widget nil "The Samples checklist widget.")
(defvar-local reader-theme-form--applied nil
  "Non-nil while Apply is on: plist (:themes PRIOR :rules RULES-MODE-WAS-ON).")

(defconst reader-theme-form--preview-theme 'reader-theme-form-preview
  "The theme Apply enables.")

(defvar-keymap reader-theme-form-mode-map
  :parent widget-keymap
  "C-c C-c" #'reader-theme-form-save
  "C-c C-k" #'reader-theme-form-cancel)

(defvar-keymap reader-theme-form-field-map
  :parent widget-field-keymap
  "C-c C-c" #'reader-theme-form-save
  "C-c C-k" #'reader-theme-form-cancel
  "C-c C-a" #'themer-picker-adjust)

(define-derived-mode reader-theme-form-mode nil "Reader-Theme"
  "Form for a reader theme.
\\{reader-theme-form-mode-map}"
  (setq-local font-lock-defaults nil)
  (setq truncate-lines t))

(defun reader-theme-form--value (key)
  "The trimmed text of field KEY."
  (when-let* ((w (alist-get key reader-theme-form--widgets)))
    (string-trim (widget-value w))))

(defun reader-theme-form--state ()
  "The form's fields as a state (see the Model commentary)."
  (list :name (or (reader-theme-form--value :name) "")
        :doc (or (reader-theme-form--value :doc) "")
        :palette (mapcar (lambda (row)
                           (list (string-trim (widget-value (plist-get row :name)))
                                 (string-trim (widget-value (plist-get row :hex)))))
                         reader-theme-form--palette-rows)
        :slots (mapcar (lambda (k) (cons k (or (reader-theme-form--value k) "")))
                       (reader-theme-form--keys))))

(defun reader-theme-form--values ()
  "Plist of the form's slots: hex, palette name, nil when empty, or :bad."
  (reader-theme-form-state-values (reader-theme-form--state)))

(defun reader-theme-form-state-model (state model)
  "MODEL with the name, doc and spec of form STATE.
Signal a `user-error' if a field can't be saved."
  (cl-loop for (text) in (plist-get state :palette)
           for row in (reader-theme-form-palette-check (plist-get state :palette))
           when (nth 2 row) do (user-error "Palette entry %S: %s" text (nth 2 row)))
  (let ((vals (reader-theme-form-state-values state))
        (name (plist-get state :name)))
    (cl-loop for (k v) on vals by #'cddr
             when (eq v :bad) do (user-error "%s is not a #rrggbb colour or palette name" k))
    (when (string-empty-p name) (user-error "The theme needs a name"))
    (let ((pal (mapcar (lambda (e) (list (car e) (cdr e))) (reader-theme-form-state-palette state))))
      (plist-put (plist-put (plist-put (copy-sequence model) :name (intern name))
                            :doc (plist-get state :doc))
                 :spec (reader-theme-form--merge-spec (plist-get model :spec)
                                                       (append (list :palette pal) vals))))))

(defun reader-theme-form-model ()
  "The model of the form as edited."
  (reader-theme-form-state-model (reader-theme-form--state) reader-theme-form--model))

(defun reader-theme-form--swatch (hex bg &optional bold)
  "A swatch for HEX on BG: a block and sample text, BOLD if non-nil."
  (concat (propertize "  " 'face `(:background ,hex))
          (propertize " Abc " 'face `(:foreground ,hex :background ,bg
                                                  :weight ,(if bold 'bold 'normal)))))

(defun reader-theme-form--status-string (items)
  "Status ITEMS, a list of (SEVERITY . TEXT), as one string."
  (mapconcat (pcase-lambda (`(,sev . ,text))
               (propertize text 'face (pcase sev ('must 'error) ('should 'warning) (_ 'shadow))))
             items "; "))

(defun reader-theme-form--update-swatches (derived)
  "Repaint swatches and statuses from the fields and DERIVED (may be nil)."
  (let* ((state (reader-theme-form--state))
         (vals (reader-theme-form-state-values state))
         (hexes (reader-theme-form-state-resolved state))
         (tiers (plist-get derived :tiers))
         (bg (or (and (stringp (plist-get hexes :bg)) (plist-get hexes :bg))
                 (plist-get tiers :bg)
                 (reader-theme-form--to-hex (face-background 'default nil t))
                 "#000000"))
         (statuses (and derived (reader-theme-form-statuses derived))))
    ;; Palette rows
    (cl-loop for row in reader-theme-form--palette-rows
             for (name hex problem) in (reader-theme-form-palette-check (plist-get state :palette))
             for users = (and name (reader-theme-form-palette-users state (symbol-name name)))
             do (overlay-put
                 (plist-get row :overlay) 'after-string
                 (concat (if hex (reader-theme-form--swatch hex bg) (make-string 7 ?\s)) "  "
                         (if hex
                             (format "%-7s Lc %5.1f  " (reader-theme-form--hue hex)
                                     (reader-theme-form--lc hex bg))
                           (make-string 18 ?\s))
                         (cond (problem (propertize problem 'face 'error))
                               (users (mapconcat (lambda (k) (substring (symbol-name k) 1)) users ", "))
                               (t (propertize "(unused)" 'face 'shadow))))))
    ;; Slots
    (pcase-dolist (`(,key ,_label ,_section ,required ,note) reader-theme-form--fields)
      (let* ((v (plist-get vals key))
             (h (plist-get hexes key))
             (shown (cond ((stringp h) h)
                          ((and (null h) tiers (memq key '(:error :warning :added :removed :popout :accent)))
                           (plist-get tiers key))))
             (status
              (cond ((eq v :bad) (propertize "not a #rrggbb colour or palette name" 'face 'error))
                    ((eq h :bad) (propertize (format "palette entry %s is not usable" v) 'face 'error))
                    ((and (null v) required) (propertize "required" 'face 'error))
                    ((and (null v) shown) (propertize (format "default %s" shown) 'face 'shadow))
                    ((null v) (propertize (pcase key
                                            (:type "none: types use callable")
                                            (:meta "none: meta uses syntax")
                                            (_ "none"))
                                          'face 'shadow))
                    (t (concat (if (symbolp v) (propertize (concat h "  ") 'face 'shadow) "")
                               (if statuses
                                   (reader-theme-form--status-string (alist-get key statuses))
                                 ""))))))
        (when-let* ((ov (alist-get key reader-theme-form--overlays)))
          (overlay-put ov 'after-string
                       (concat (if shown (reader-theme-form--swatch shown bg) (make-string 7 ?\s))
                               "  " (propertize (format "%-34s" note) 'face 'shadow)
                               status)))))))

(defun reader-theme-form--insert-tiers (derived)
  "Insert the derived tiers of DERIVED."
  (let* ((tiers (plist-get derived :tiers))
         (bg (plist-get tiers :bg))
         (cell (lambda (hex &optional bold)
                 (if hex
                     (format "%s %s %4.1f" (reader-theme-form--swatch hex bg bold) hex
                             (reader-theme-form--lc hex bg))
                   (format "%-20s" "-")))))
    (widget-insert (propertize "Derived tiers" 'face 'bold) "  (swatch, hex, Lc)\n")
    (insert (format "  %-12s %-20s  %-20s  %-20s  %-20s\n" "" "recessive" "quiet" "loud" "strong"))
    (dolist (fam reader-theme-families)
      (let ((loud (alist-get fam (plist-get tiers :loud))))
        (insert (format "  %-12s " (if (and (not loud) (plist-get (plist-get derived :spec)
                                                                  (intern (format ":%s" fam))))
                                       (format "%s (shed)" fam)
                                     fam))
                (funcall cell (and (eq fam 'syntax) (plist-get tiers :recessive))) "  "
                (funcall cell (alist-get fam (plist-get tiers :quiet))) "  "
                (funcall cell loud) "  "
                (funcall cell loud t) "\n")))
    (insert (format "  %-12s " "neutral")
            "default " (funcall cell (plist-get tiers :fg))
            "  dim " (funcall cell (plist-get tiers :dim))
            "  faded " (funcall cell (plist-get tiers :faded)) "\n")
    (insert (format "  %-12s " "cues")
            "binding " (funcall cell (plist-get tiers :binding))
            "  popout " (funcall cell (plist-get tiers :popout) t)
            "  accent " (funcall cell (plist-get tiers :accent) t) "\n")))

(defun reader-theme-form--insert-conformance (derived)
  "Insert the conformance panel of DERIVED."
  (let ((conf (plist-get derived :conformance)))
    (insert (propertize "Conformance" 'face 'bold)
            (format "  level %s  (normal vision %s, with CVD %s)\n"
                    (propertize (plist-get conf :level) 'face 'bold)
                    (plist-get conf :level-normal) (plist-get conf :level-cvd)))
    (dolist (c (plist-get conf :checks))
      (unless (eq (plist-get c :id) 'level)
        (insert (format "  %s %-6s %-3s %s\n"
                        (if (plist-get c :ok) (propertize "ok  " 'face 'success)
                          (propertize "FAIL" 'face (if (eq (plist-get c :keyword) 'MUST) 'error 'warning)))
                        (plist-get c :keyword) (plist-get c :section) (plist-get c :detail)))))))

(defun reader-theme-form--update-dynamic (derived &optional message)
  "Redraw the sections after the fields from DERIVED, or show MESSAGE."
  (let ((inhibit-read-only t) (inhibit-modification-hooks t))
    (save-excursion
      (delete-region reader-theme-form--dynamic (point-max))
      (goto-char reader-theme-form--dynamic)
      (if (not derived)
          (insert (propertize (or message "") 'face 'shadow) "\n")
        (reader-theme-form--insert-tiers derived)
        (insert "\n")
        (reader-theme-form--insert-conformance derived)))))

(defun reader-theme-form-refresh (&optional buffer interruptible)
  "Re-derive the form in BUFFER if a colour changed, and redraw.
With INTERRUPTIBLE, input aborts the derivation and reschedules it."
  (let ((buffer (or buffer (current-buffer))))
    (when (buffer-live-p buffer)
      (with-current-buffer buffer
        (let* ((state (reader-theme-form--state))
               (vals (reader-theme-form-state-resolved state))
               (bad (append
                     (cl-loop for (name _ problem) in (reader-theme-form-palette-check
                                                       (plist-get state :palette))
                              for (text) in (plist-get state :palette)
                              when problem collect (if name (symbol-name name)
                                                     (format "palette entry %S" text)))
                     (cl-loop for (k v) on vals by #'cddr
                              when (or (eq v :bad)
                                       (and (null v) (nth 3 (assq k reader-theme-form--fields))))
                              collect (substring (symbol-name k) 1))))
               (spec (cl-loop for (k v) on vals by #'cddr when (stringp v) append (list k v))))
          (cond
           (bad
            (reader-theme-form--update-swatches nil)
            (reader-theme-form--update-dynamic
             nil (format "Fix %s to derive the theme." (string-join bad ", "))))
           ((equal spec (plist-get reader-theme-form--derived :spec))
            (reader-theme-form--update-swatches reader-theme-form--derived))
           (t
            (let ((d (if interruptible
                         (while-no-input (redisplay) (reader-theme-derive spec))
                       (reader-theme-derive spec))))
              (if (eq d t)
                  (reader-theme-form--schedule)  ; interrupted by input
                (setq reader-theme-form--derived d)
                (reader-theme-form--update-swatches d)
                (reader-theme-form--update-dynamic d)
                (themer-samples-update (reader-theme-faces d))
                (when reader-theme-form--applied
                  (reader-theme-form--define-preview d)))))))))))

(defun reader-theme-form--schedule (&rest _)
  "Refresh the form after `themer-preview-delay' idle seconds."
  (when (timerp reader-theme-form--timer)
    (cancel-timer reader-theme-form--timer))
  (setq reader-theme-form--timer
        (run-with-idle-timer (if (boundp 'themer-preview-delay) themer-preview-delay 0.4)
                             nil #'reader-theme-form-refresh (current-buffer) t)))

;;;; Apply

(defun reader-theme-form--define-preview (derived)
  "Set the preview theme's faces from DERIVED and enable it."
  (let ((th reader-theme-form--preview-theme))
    (unless (custom-theme-p th)
      (custom-declare-theme th nil "Preview of a reader theme form."))
    (put th 'theme-settings nil)
    (reader-theme-define th (plist-get derived :spec))
    (enable-theme th)))

(defun reader-theme-form--apply (on)
  "Turn Apply ON or off."
  (cond
   ((and on (not reader-theme-form--applied))
    (unless reader-theme-form--derived
      (user-error "Fix the colours first"))
    (setq reader-theme-form--applied
          (list :themes custom-enabled-themes :rules reader-theme-treesit-mode))
    (mapc #'disable-theme custom-enabled-themes)
    (reader-theme-form--define-preview reader-theme-form--derived))
   ((and (not on) reader-theme-form--applied)
    (let ((prior reader-theme-form--applied)
          (th reader-theme-form--preview-theme))
      (setq reader-theme-form--applied nil)
      (when (custom-theme-p th)
        (disable-theme th)
        (put th 'theme-settings nil)
        (setq custom-known-themes (delq th custom-known-themes)))
      (dolist (x (reverse (plist-get prior :themes)))
        (enable-theme x))
      (unless (eq (and reader-theme-treesit-mode t) (and (plist-get prior :rules) t))
        (reader-theme-treesit-mode (if (plist-get prior :rules) 1 -1)))))))

(defun reader-theme-form--cleanup ()
  "Undo Apply and stop the timer: for `kill-buffer-hook'."
  (when (timerp reader-theme-form--timer)
    (cancel-timer reader-theme-form--timer))
  (reader-theme-form--apply nil)
  (themer-samples-kill))

;;;; Building the form

(defun reader-theme-form--button (label fn)
  "Insert a push button LABEL calling FN with no arguments."
  (widget-create 'push-button :notify (lambda (&rest _) (funcall fn)) label))

(defun reader-theme-form--field (key value size)
  "Insert an editable field for KEY with VALUE and SIZE."
  (let ((w (widget-create 'editable-field :size size :format "%v" :value (or value "")
                          :keymap reader-theme-form-field-map
                          :notify #'reader-theme-form--schedule)))
    (push (cons key w) reader-theme-form--widgets)
    w))

(defun reader-theme-form--palette-row (name hex)
  "Insert a palette row for entry NAME with colour HEX, and return it."
  (let* ((nw (widget-create 'editable-field :size 14 :format "%v" :value name
                            :keymap reader-theme-form-field-map
                            :themer-name name
                            :notify #'reader-theme-form--name-notify))
         (_ (widget-insert " "))
         (hw (widget-create 'editable-field :size 8 :format "%v" :value hex
                            :keymap reader-theme-form-field-map
                            :notify #'reader-theme-form--schedule))
         (row (list :name nw :hex hw)))
    (widget-insert " ")
    (reader-theme-form--button "Pick" (lambda () (reader-theme-form--palette-pick row)))
    (widget-insert " ")
    (reader-theme-form--button "Rename" (lambda () (reader-theme-form-palette-rename-entry row)))
    (widget-insert " ")
    (reader-theme-form--button "Delete" (lambda () (reader-theme-form-palette-delete-entry row)))
    (widget-insert " ")
    (plist-put row :overlay (make-overlay (1- (point)) (point)))))

(defun reader-theme-form--render (model &optional state)
  "Draw the form for MODEL in the current buffer.
The fields show STATE, a form state, if given, else MODEL."
  (let ((applied reader-theme-form--applied))
    (reader-theme-form-mode)
    (setq reader-theme-form--applied applied))
  (setq themer-samples-title (reader-theme-form--samples-title (plist-get model :name))
        themer-samples-setup-function #'reader-theme--install)
  (let ((inhibit-read-only t)) (erase-buffer))
  (remove-overlays)
  (add-hook 'kill-buffer-hook #'reader-theme-form--cleanup nil t)
  (setq reader-theme-form--model model
        reader-theme-form--widgets nil
        reader-theme-form--overlays nil
        reader-theme-form--palette-rows nil
        reader-theme-form--derived nil)
  (let ((state (or state (reader-theme-form-model-state model))))
    (widget-insert (propertize "Reader theme" 'face 'bold)
                   (if-let* ((f (plist-get model :file))) (format "  %s" (abbreviate-file-name f)) "  (new)")
                   "\n\n")
    (reader-theme-form--button "Save" #'reader-theme-form-save) (widget-insert " ")
    (reader-theme-form--button "Export standalone" #'reader-theme-form-export) (widget-insert " ")
    (reader-theme-form--button "Import base16" #'reader-theme-form-import-base16) (widget-insert " ")
    (reader-theme-form--button "Revert" #'reader-theme-form-revert) (widget-insert " ")
    (reader-theme-form--button "Check" #'reader-theme-form-check) (widget-insert "  ")
    (setq reader-theme-form--apply-widget
          (widget-create 'checkbox :notify (lambda (w &rest _)
                                             (condition-case err
                                                 (reader-theme-form--apply (widget-value w))
                                               (user-error (widget-value-set w nil)
                                                           (message "%s" (error-message-string err)))))
                         (and reader-theme-form--applied t)))
    (widget-insert " Apply (preview globally)\n\n")
    (widget-insert (format "  %-11s " "Name"))
    (reader-theme-form--field :name (plist-get state :name) 30)
    (widget-insert "\n" (format "  %-11s " "Description"))
    (reader-theme-form--field :doc (plist-get state :doc) 60)
    (widget-insert "\n\n" (propertize "Palette" 'face 'bold)
                   "  (named colours; a slot takes a name or a hex)\n")
    (dolist (e (plist-get state :palette))
      (widget-insert "  ")
      (push (reader-theme-form--palette-row (car e) (cadr e)) reader-theme-form--palette-rows)
      (widget-insert "\n"))
    (setq reader-theme-form--palette-rows (nreverse reader-theme-form--palette-rows))
    (widget-insert "  ")
    (reader-theme-form--button "Add" #'reader-theme-form-palette-add-entry)
    (widget-insert "\n")
    (let (section)
      (pcase-dolist (`(,key ,label ,sec ,required ,_note) reader-theme-form--fields)
        (unless (eq sec section)
          (setq section sec)
          (widget-insert "\n" (propertize (pcase sec ('base "Base") ('family "Families")
                                                 ('cue "Optional cues") ('ui "UI")
                                                 ('convention "Conventions"))
                                          'face 'bold)
                         (pcase sec ('cue "  (empty: none / automatic)")
                                ('ui "  (empty: popout, else callable; never colours syntax)")
                                ('convention "  (empty: derived default)") (_ ""))
                         "\n"))
        (widget-insert (format "  %-11s " (concat label (if required "" "?"))))
        (reader-theme-form--field key (alist-get key (plist-get state :slots)) 14)
        (widget-insert " ")
        (reader-theme-form--button "Pick" (lambda () (reader-theme-form-pick key)))
        (widget-insert " ")
        (let ((ov (make-overlay (1- (point)) (point))))
          (push (cons key ov) reader-theme-form--overlays))
        (widget-insert "\n")))
    (widget-insert "\n" (propertize "Samples" 'face 'bold)
                   (format "  (shown in their own buffers, %d at once)  " themer-samples-max))
    (reader-theme-form--button "Show samples" #'themer-samples-show)
    (widget-insert "\n  ")
    (setq reader-theme-form--samples-widget
          (apply #'widget-create 'checklist
                 :value (themer-samples-selected-languages)
                 :entry-format "%b %v   "
                 :notify (lambda (w &rest _)
                           (themer-samples-set-languages (widget-value w))
                           ;; Untick the language that gave way, if one did.
                           (let ((shown (themer-samples-selected-languages)))
                             (unless (seq-set-equal-p shown (widget-value w))
                               (save-excursion (widget-value-set w shown))
                               (widget-setup))))
                 (mapcar (lambda (e)
                           `(item :tag ,(themer-samples-language-name (car e))
                                  :format "%t" :value ,(car e)))
                         (themer-samples-list))))
    (widget-insert "\n\n")
    (setq reader-theme-form--dynamic (point-marker))
    (widget-insert "\n"))
  (use-local-map reader-theme-form-mode-map)
  (widget-setup)
  (reader-theme-form--update-swatches nil)
  (reader-theme-form--update-dynamic nil "Deriving...")
  (goto-char (point-min))
  (widget-forward 1))

(defun reader-theme-form--rerender (state &optional goto)
  "Redraw the form with STATE and re-derive, keeping point's line and column.
With GOTO, a function, call it afterwards to place point."
  (let ((line (line-number-at-pos)) (col (current-column)))
    (reader-theme-form--render reader-theme-form--model state)
    (goto-char (point-min))
    (forward-line (1- line))
    (move-to-column col)
    (when goto (funcall goto))
    (reader-theme-form-refresh)))

(defun reader-theme-form--open (model)
  "Open a form buffer for MODEL and return it."
  (let ((buf (generate-new-buffer (format "*reader-theme %s*" (or (plist-get model :name) "new")))))
    (with-current-buffer buf
      (reader-theme-form--render model)
      (setq reader-theme-form--timer
            (run-with-timer 0 nil #'reader-theme-form-refresh buf t)))
    ;; The selected window, not a new split, so the form keeps the room it
    ;; had and the samples are split off it.
    (pop-to-buffer-same-window buf)
    (with-current-buffer buf (themer-samples-show))
    buf))

;;;; Commands

(defun reader-theme-form--seed-model (seed)
  "A new model seeded from SEED: a theme file, a spec plist, or nil."
  (let ((m (cond ((stringp seed) (reader-theme-form-read-file seed))
                 (seed (list :spec seed)))))
    (list :name (and (plist-get m :name) (intern (format "%s-copy" (plist-get m :name))))
          :doc (or (plist-get m :doc) "")
          :spec (or (plist-get m :spec)
                    (let ((bg (reader-theme-form--to-hex (face-background 'default nil t)))
                          (fg (reader-theme-form--to-hex (face-foreground 'default nil t))))
                      (and bg fg (list :palette `((bg ,bg) (fg ,fg)) :bg 'bg :fg 'fg)))))))

;;;###autoload
(defun reader-theme-new (&optional seed)
  "Open a form for a new reader theme, seeded from SEED.
SEED is a reader theme file or a spec plist; interactively, a theme
chosen by name (empty for a form with only the current colours)."
  (interactive (list (reader-theme-form--read-theme-file "Seed from theme (empty for none): ")))
  (reader-theme-form--open (reader-theme-form--seed-model seed)))

;;;###autoload
(defun reader-theme-edit (&optional file)
  "Open a form on reader theme FILE.
Interactively, this buffer's theme file if it has a reader theme, else
one chosen by name from `custom-theme-load-path' and
`reader-theme-directory'."
  (interactive
   (list (or (and buffer-file-name (reader-theme-form--deftheme-bounds) buffer-file-name)
             (reader-theme-form--read-theme-file "Edit reader theme: ")
             (user-error "No theme chosen"))))
  (reader-theme-form--open
   (if-let* ((buf (get-file-buffer file))
             ((with-current-buffer buf (reader-theme-form--deftheme-bounds))))
       (with-current-buffer buf (reader-theme-form-parse (buffer-string) (expand-file-name file)))
     (reader-theme-form-read-file file))))

;;;###autoload
(defun reader-theme-screenshot (theme-file file &optional languages settle)
  "Write a picture of the form on THEME-FILE, with its samples, to FILE.
FILE is a .png, .svg or .pdf.  The form opens in a frame of its own,
`themer-render-frame-size' large, which is deleted afterwards.
LANGUAGES, at most `themer-samples-max', are the samples shown; nil
means the current choice.  SETTLE is as for `themer-render-frame-with'."
  (interactive
   (list (or (reader-theme-form--read-theme-file "Picture of reader theme: ")
             (user-error "No theme chosen"))
         (read-file-name "Write picture to: " nil nil nil "reader-theme.png")))
  (let ((themer-samples--selected (or languages themer-samples--selected)))
    (themer-render-frame-with
     file (lambda ()
            ;; Derive now: the settle wait isn't idle, so the form's own
            ;; refresh may never run.
            (let ((form (reader-theme-edit theme-file)))
              (reader-theme-form-refresh form)
              form))
     nil settle)))

(defun reader-theme-form-save (&optional file)
  "Save the form's theme to FILE.
FILE defaults to the edited file (renamed with the theme), else
`reader-theme-directory'.  With a prefix argument, ask."
  (interactive
   (list (when current-prefix-arg
           (read-file-name "Save theme to: " nil nil nil
                           (format "%s-theme.el" (reader-theme-form--value :name))))))
  (let* ((model (reader-theme-form-model))
         (file (expand-file-name (or file (reader-theme-form--default-file model)))))
    (when (and (file-exists-p file)
               (not (equal file (plist-get model :file)))
               (called-interactively-p 'any)
               (not (y-or-n-p (format "%s exists; overwrite? " file))))
      (user-error "Not saved"))
    (let ((new (reader-theme-form-write model file)))
      (setq reader-theme-form--model new)
      ;; A theme saved anywhere becomes loadable in this session.
      (reader-theme-add-directory (file-name-directory file))
      (when-let* ((buf (get-file-buffer file))
                  ((not (buffer-modified-p buf))))
        (with-current-buffer buf (revert-buffer t t t)))
      (rename-buffer (format "*reader-theme %s*" (plist-get new :name)) t)
      (themer-samples-retitle (reader-theme-form--samples-title (plist-get new :name)))
      (message "Wrote %s" file)
      file)))

(defun reader-theme-form-cancel ()
  "Kill the form, asking first if it has unsaved changes."
  (interactive)
  (when (or (not (called-interactively-p 'any))
            (equal (ignore-errors (reader-theme-form-source (reader-theme-form-model)))
                   (ignore-errors (reader-theme-form-source reader-theme-form--model)))
            (y-or-n-p "Discard unsaved changes? "))
    (let ((buf (current-buffer)))
      (quit-window nil)
      (kill-buffer buf))))

(defun reader-theme-form-revert ()
  "Put the form back to the model it was opened on, or last saved."
  (interactive)
  (let ((m reader-theme-form--model))
    (reader-theme-form--render
     (if-let* ((f (plist-get m :file)) ((file-exists-p f))) (reader-theme-form-read-file f) m))
    (reader-theme-form-refresh)))

(defun reader-theme-form-check ()
  "Show the full conformance report for the form's theme."
  (interactive)
  (reader-theme-form-refresh)
  (unless reader-theme-form--derived (user-error "Fix the colours first"))
  (let ((name (reader-theme-form--value :name)) (d reader-theme-form--derived))
    (with-help-window "*reader-theme-check*"
      (with-current-buffer standard-output
        (reader-theme-report name d)))))

(defun reader-theme-form-export (&optional file)
  "Export the form's theme to FILE as a standalone theme."
  (interactive)
  (let* ((m (reader-theme-form-model))
         (file (or file (read-file-name "Export theme to: " nil nil nil
                                        (format "%s-theme.el" (plist-get m :name))))))
    (reader-theme-export file nil (plist-get m :name) (plist-get m :spec))))

(defun reader-theme-form--set (key text)
  "Set slot field KEY to TEXT: a hex or a palette name."
  (widget-value-set (alist-get key reader-theme-form--widgets) (or text ""))
  (widget-setup))

(defun reader-theme-form--read-hex (prompt)
  "Read a colour with `read-color' and PROMPT, as a lower-case hex."
  (let* ((c (read-color prompt))
         (hex (reader-theme-form--to-hex c)))
    (or hex (user-error "Unknown colour %s" c))))

(defun reader-theme-form-read-pick (prompt palette &optional current)
  "Read a slot's colour with PROMPT from the Pick menu of PALETTE.
PALETTE is an alist (NAME . HEX); CURRENT the field's text, the default.
Return a palette name (a symbol), a hex typed in, `custom' or `add'."
  (let* ((cands (reader-theme-form-pick-candidates palette))
         (table (lambda (str pred action)
                  (if (eq action 'metadata)
                      `(metadata (category . themer-palette)
                                 (display-sort-function . identity)
                                 (annotation-function
                                  . ,(reader-theme-form--pick-annotation palette)))
                    (complete-with-action action cands str pred))))
         (choice (string-trim (completing-read prompt table nil nil nil nil
                                               (and current (not (string-empty-p current)) current)))))
    (cond ((assoc choice cands) (cdr (assoc choice cands)))
          ((themer-colour-hex-p choice) (downcase choice))
          ((string-empty-p choice) (user-error "No colour chosen"))
          (t (user-error "%s is not a palette entry or #rrggbb colour" choice)))))

(defun reader-theme-form-pick (key)
  "Choose the colour of slot KEY from a menu of the palette entries.
The menu also has \"Custom hex…\" (`read-color') and \"Add to palette…\"
\(a new entry, which the slot then names)."
  (interactive (list (intern (completing-read "Field: " (mapcar #'car reader-theme-form--fields)))))
  (let* ((state (reader-theme-form--state))
         (label (nth 1 (assq key reader-theme-form--fields)))
         (choice (reader-theme-form-read-pick (format "%s: " label)
                                               (reader-theme-form-state-palette state)
                                               (alist-get key (plist-get state :slots)))))
    (pcase choice
      ('custom
       (reader-theme-form--set key (reader-theme-form--read-hex (format "%s (name or #rrggbb): " label)))
       (reader-theme-form--schedule))
      ('add
       (let* ((hex (reader-theme-form--read-hex "New palette colour (name or #rrggbb): "))
              (def (reader-theme-form-suggest-name state hex))
              (name (string-trim (read-string (format "Name for %s (default %s): " hex def) nil nil def))))
         (reader-theme-form--rerender
          (reader-theme-form-set-slot (reader-theme-form-palette-add state name hex) key name))))
      ((pred symbolp)
       (reader-theme-form--set key (symbol-name choice))
       (reader-theme-form--schedule))
      (_
       (reader-theme-form--set key choice)
       (reader-theme-form--schedule)))))

(defun reader-theme-form--row-name (row)
  "The text of palette ROW's name field."
  (string-trim (widget-value (plist-get row :name))))

(defun reader-theme-form--palette-pick (row)
  "Pick the colour of palette ROW with `read-color'."
  (let ((hex (reader-theme-form--read-hex
              (format "Colour of %s (name or #rrggbb): " (reader-theme-form--row-name row)))))
    (widget-value-set (plist-get row :hex) hex)
    (widget-setup)
    (reader-theme-form--schedule)))

(defun reader-theme-form--goto-row (index)
  "Move point to the name field of palette row INDEX."
  (when-let* ((row (nth index reader-theme-form--palette-rows)))
    (goto-char (widget-field-start (plist-get row :name)))))

(defun reader-theme-form-palette-add-entry ()
  "Add a palette entry: read its colour and name."
  (interactive)
  (let* ((state (reader-theme-form--state))
         (hex (reader-theme-form--read-hex "New palette colour (name or #rrggbb): "))
         (def (reader-theme-form-suggest-name state hex))
         (name (string-trim (read-string (format "Name for %s (default %s): " hex def) nil nil def)))
         (new (reader-theme-form-palette-add state name hex)))
    (reader-theme-form--rerender
     new (lambda () (reader-theme-form--goto-row (1- (length (plist-get new :palette))))))))

(defun reader-theme-form-palette-rename-entry (row)
  "Rename palette ROW, and every slot that names it."
  (let* ((state (reader-theme-form--state))
         (old (reader-theme-form--row-name row))
         (index (cl-position row reader-theme-form--palette-rows))
         (new (string-trim (read-string (format "Rename %s to: " old) old))))
    (unless (equal new old)
      (reader-theme-form--rerender (reader-theme-form-palette-rename state old new)
                                    (lambda () (reader-theme-form--goto-row index))))))

(defun reader-theme-form-palette-delete-entry (row)
  "Delete palette ROW.
If slots name it, ask first; they then take its hex."
  (let* ((state (reader-theme-form--state))
         (name (reader-theme-form--row-name row))
         (index (cl-position row reader-theme-form--palette-rows))
         (users (unless (cl-find name (remq (nth index (plist-get state :palette)) (plist-get state :palette))
                                 :key #'car :test #'equal)
                  (reader-theme-form-palette-users state name))))
    (when (and users
               (not (y-or-n-p (format "%s is used by %s; delete it and put its hex there? " name
                                      (mapconcat (lambda (k) (substring (symbol-name k) 1)) users ", ")))))
      (user-error "Not deleted"))
    (reader-theme-form--rerender
     (reader-theme-form-palette-delete state index t)
     (lambda () (reader-theme-form--goto-row (min index (1- (length reader-theme-form--palette-rows))))))))

(defun reader-theme-form--name-notify (widget &rest _)
  "Rename the palette entry of name field WIDGET as it is typed.
Once the text is a usable name no other entry has, the slots that named
the entry name it again."
  (let* ((old (widget-get widget :themer-name))
         (new (string-trim (widget-value widget)))
         (others (cl-loop for row in reader-theme-form--palette-rows
                          unless (eq (plist-get row :name) widget)
                          collect (reader-theme-form--row-name row))))
    (when (and (not (equal old new)) (reader-theme-form-name-ok new) (not (member new others)))
      (unless (member old others)
        (pcase-dolist (`(,key . ,w) reader-theme-form--widgets)
          (when (and (memq key (reader-theme-form--keys))
                     (reader-theme-form-name-ok old)
                     (equal (string-trim (widget-value w)) old))
            (save-excursion (widget-value-set w new)))))
      (widget-put widget :themer-name new)))
  (reader-theme-form--schedule))

(defconst reader-theme-form--base16-defaults
  '((:bg "base00") (:fg "base05") (:syntax "base0E") (:callable "base0D") (:type "base0A")
    (:value "base09") (:meta "base0C") (:error red) (:warning yellow) (:added green))
  "Default base16 slot per field; a hue name means the first accent slot with it.")

(defun reader-theme-form-base16-defaults (slots)
  "Alist KEY -> slot name: the default mapping of base16 SLOTS."
  (cl-loop for (key d) in reader-theme-form--base16-defaults
           collect (cons key (if (stringp d) d
                               (car (cl-find-if (lambda (s) (and (string-match-p "\\`base0[89A-F]" (car s))
                                                                 (eq (themer-colour-hue-name (cdr s)) d)))
                                                slots))))))

(defun reader-theme-form-import-base16 (&optional file)
  "Fill the palette from base16 (or base24) YAML FILE, and point the slots at it.
The palette gets an entry per slot, base00 to base0F (base17); each
field is asked which slot it names, defaulting to the base16 conventions."
  (interactive)
  (let* ((file (or file (read-file-name "base16 YAML: " nil nil t)))
         (slots (or (reader-theme--read-base16 file) (user-error "No base16 slots in %s" file)))
         (choices (mapcar (lambda (s) (cons (format "%s %s %s" (car s) (cdr s) (reader-theme-form--hue (cdr s)))
                                            (car s)))
                          slots))
         (picked
          (cl-loop for (key . slot) in (reader-theme-form-base16-defaults slots)
                   collect
                   (let* ((label (nth 1 (assq key reader-theme-form--fields)))
                          (def (car (cl-find-if (lambda (c) (and slot (equal slot (cdr c)))) choices)))
                          (c (completing-read (format "%s slot: " label) (cons "(none)" (mapcar #'car choices))
                                              nil t nil nil (or def "(none)"))))
                     (cons key (cdr (assoc c choices)))))))
    (reader-theme-form--rerender
     (reader-theme-form-base16-state (reader-theme-form--state) slots picked))))

(provide 'reader-theme-form)

;;; reader-theme-form.el ends here
