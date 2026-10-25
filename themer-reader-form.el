;;; themer-reader-form.el --- A form for creating and editing reader themes -*- lexical-binding: t; -*-

;; Author: beltsmith <me@alexgirdler.com>
;; Package-Requires: ((emacs "29.1"))

;;; Commentary:
;;
;; A customize-like form (widget.el) for reader themes:
;;
;;   `themer-reader-new-theme'   open an empty form, or one seeded from a theme
;;   `themer-reader-edit-theme'  open the form on a reader theme file
;;
;; The palette comes first: one row per named colour, with its name, hex,
;; a swatch on the theme's background, its hue and Lc, and the slots that
;; use it.  Each slot then names a palette entry or holds a raw hex, with a
;; swatch, a "Pick" button (a menu of the palette entries, a custom hex, or
;; a new entry) and a short status from the conformance result.  Below them
;; are the derived tiers and the conformance checks.  The code samples
;; (TypeScript, Python, Rust, C, Go, Emacs Lisp; a checkbox each) are drawn
;; with the derived faces in their own buffer beside the form,
;; `*themer-reader-sample: NAME*'.  Edits re-derive after
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
(require 'themer-reader)
(require 'themer-picker)

(defvar themer-preview-delay)
(defvar treesit-font-lock-level)
(defvar eglot-sync-connect)
(defvar eglot--semtok-state)
(defvar eglot-semantic-tokens-mode)
(declare-function eglot "eglot")
(declare-function eglot--guess-contact "eglot")
(declare-function eglot--lookup-mode "eglot")
(declare-function eglot--managed-buffers "eglot")
(declare-function eglot-current-server "eglot")
(declare-function eglot-managed-p "eglot")
(declare-function eglot-server-capable "eglot")
(declare-function eglot-semantic-tokens-mode "eglot")
(declare-function eglot-shutdown "eglot")
(declare-function custom-theme--load-path "custom")

;;;; Model
;;
;; A model is a plist (:name SYMBOL :doc STRING :spec PLIST :file FILE
;; :prefix STRING :suffix STRING :orig (NAME . DOC) :form STRING
;; :orig-spec PLIST).  :prefix and :suffix are the file text around the
;; `themer-reader-deftheme' form, kept as is when saving; :form is the
;; form's own text, kept while the name, doc and spec are unchanged.
;;
;; The form's fields are read into a state, a plist (:name STRING :doc
;; STRING :palette ((NAME HEX)...) :slots ((KEY . TEXT)...)) of the texts
;; as typed.  The palette operations (add, rename, delete) work on states.

(defconst themer-reader-form--fields
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

(defun themer-reader-form--keys ()
  "The colour keys in spec order."
  (mapcar #'car themer-reader-form--fields))

(defconst themer-reader-form--custom "Custom hex…"
  "The Pick menu entry for a colour not in the palette.")

(defconst themer-reader-form--add "Add to palette…"
  "The Pick menu entry for a new palette entry.")

(defun themer-reader-form--deftheme-bounds ()
  "Bounds (BEG . END) of the `themer-reader-deftheme' form in this buffer."
  (save-excursion
    (goto-char (point-min))
    (when (re-search-forward "^(themer-reader-deftheme\\_>" nil t)
      (let ((beg (match-beginning 0)))
        (with-syntax-table emacs-lisp-mode-syntax-table
          (cons beg (scan-sexps beg 1)))))))

(defun themer-reader-form-parse (text &optional file)
  "The form model of theme source TEXT, from FILE if given."
  (with-temp-buffer
    (insert text)
    (let* ((bounds (or (themer-reader-form--deftheme-bounds)
                       (user-error "No themer-reader-deftheme form%s"
                                   (if file (format " in %s" file) ""))))
           (text (buffer-substring-no-properties (car bounds) (cdr bounds)))
           (form (read text))
           (doc (nth 2 form))
           (spec (themer-reader--form-spec form)))
      (list :name (nth 1 form) :doc doc
            :spec spec
            :file file
            :prefix (buffer-substring-no-properties (point-min) (car bounds))
            :suffix (buffer-substring-no-properties (cdr bounds) (point-max))
            :orig (cons (nth 1 form) doc)
            :form text :orig-spec spec))))

(defun themer-reader-form-read-file (file)
  "The form model of reader theme FILE."
  (with-temp-buffer
    (insert-file-contents file)
    (themer-reader-form-parse (buffer-string) (expand-file-name file))))

(defun themer-reader-form--retitle (text model)
  "TEXT, around a deftheme form, with MODEL's original name and doc updated."
  (pcase-let ((`(,oname . ,odoc) (plist-get model :orig))
              (name (plist-get model :name)) (doc (plist-get model :doc)))
    (unless (eq oname name)
      (setq text (string-replace (format "%s-theme.el" oname) (format "%s-theme.el" name) text)))
    (when (and odoc (not (equal odoc doc))
               (string-match (format "\\`;;; [^ \n]+ --- \\(%s\\)" (regexp-quote odoc)) text))
      (setq text (replace-match doc t t text 1)))
    text))

(defun themer-reader-form-source (model)
  "Theme file source for MODEL.
The deftheme form is written out again unless MODEL's name, doc and spec
are those it was read with."
  (let ((name (plist-get model :name)) (doc (plist-get model :doc))
        (spec (plist-get model :spec)))
    (if (plist-get model :prefix)
        (concat (themer-reader-form--retitle (plist-get model :prefix) model)
                (if (and (plist-get model :form)
                         (equal (plist-get model :orig) (cons name doc))
                         (equal (plist-get model :orig-spec) spec))
                    (plist-get model :form)
                  (themer-reader--deftheme-source name doc spec))
                (themer-reader-form--retitle (plist-get model :suffix) model))
      (themer-reader--theme-source name doc spec))))

(defun themer-reader-form--merge-spec (old values)
  "Spec of VALUES (a plist; nil values dropped), keys in the order of spec OLD.
Keys OLD lacks follow in the canonical order; a new :palette goes first."
  (let (out)
    (cl-loop for (k _) on old by #'cddr
             when (plist-get values k) do (setq out (plist-put out k (plist-get values k))))
    (dolist (k (themer-reader-form--keys))
      (when (and (plist-get values k) (not (plist-member out k)))
        (setq out (plist-put out k (plist-get values k)))))
    (when (and (plist-get values :palette) (not (plist-member out :palette)))
      (setq out (append (list :palette (plist-get values :palette)) out)))
    out))

(defun themer-reader-form--default-file (model)
  "Where MODEL is saved: its file's directory, else the theme directory."
  (expand-file-name (format "%s-theme.el" (plist-get model :name))
                    (if-let* ((f (plist-get model :file))) (file-name-directory f)
                      themer-reader-theme-directory)))

(defun themer-reader-form-write (model &optional file)
  "Write MODEL to FILE (default `themer-reader-form--default-file').
Return MODEL updated as read back from the file."
  (themer-reader--check-spec (plist-get model :spec))
  (let ((file (expand-file-name (or file (themer-reader-form--default-file model)))))
    (make-directory (file-name-directory file) t)
    (let ((coding-system-for-write 'utf-8))
      (write-region (themer-reader-form-source model) nil file nil 'silent))
    (themer-reader-form-read-file file)))

;;;; Finding themes

(defun themer-reader-form--theme-files ()
  "Alist (NAME . FILE) of reader themes on `custom-theme-load-path'.
`themer-reader-theme-directory' is searched too."
  (let (out)
    (dolist (dir (delete-dups (append (custom-theme--load-path)
                                      (list (expand-file-name themer-reader-theme-directory)))))
      (when (file-directory-p dir)
        (dolist (f (directory-files dir t "-theme\\.el\\'"))
          (let ((name (string-remove-suffix "-theme.el" (file-name-nondirectory f))))
            (unless (assoc name out)
              (with-temp-buffer
                (insert-file-contents f nil 0 20000)
                (when (re-search-forward "^(themer-reader-deftheme\\_>" nil t)
                  (push (cons name f) out))))))))
    (nreverse out)))

(defun themer-reader-form--read-theme-file (prompt)
  "Read a reader theme with PROMPT: a name from the found themes, or a file."
  (let* ((themes (themer-reader-form--theme-files))
         (choice (completing-read prompt themes nil nil)))
    (cond ((string-empty-p choice) nil)   ; before `file-exists-p': "" is the cwd
          ((assoc choice themes) (cdr (assoc choice themes)))
          ((file-regular-p choice) (expand-file-name choice))
          (t (user-error "No reader theme %s" choice)))))

;;;; Colours

(defun themer-reader-form--to-hex (colour)
  "COLOUR (a name or hex) as \"#rrggbb\", or nil."
  (cond ((themer-colour-hex-p colour) (downcase colour))
        ((and (stringp colour) (color-defined-p colour))
         (apply #'color-rgb-to-hex (append (color-name-to-rgb colour) '(2))))))

(defun themer-reader-form--hue (hex)
  "Hue name of HEX, as a string."
  (symbol-name (themer-colour-hue-name hex)))

;;;; States and the palette (non-interactive)

(defun themer-reader-form--text (value)
  "Field text for spec VALUE: a hex, a palette name, or \"\"."
  (cond ((null value) "")
        ((symbolp value) (symbol-name value))
        (t value)))

(defun themer-reader-form-model-state (model)
  "The form state of MODEL: its fields as texts."
  (let ((spec (plist-get model :spec)))
    (list :name (if (plist-get model :name) (symbol-name (plist-get model :name)) "")
          :doc (or (plist-get model :doc) "")
          :palette (mapcar (lambda (e) (list (symbol-name (car e)) (cadr e)))
                           (plist-get spec :palette))
          :slots (mapcar (lambda (k) (cons k (themer-reader-form--text (plist-get spec k))))
                         (themer-reader-form--keys)))))

(defun themer-reader-form-name-ok (text)
  "Non-nil if TEXT can name a palette entry.
A letter or _ then letters, digits and _+*/<>=!?$%&~^-, but not t or nil."
  (and (stringp text)
       (let ((case-fold-search nil))
         (string-match-p "\\`[[:alpha:]_][[:alnum:]_+*/<>=!?$%&~^-]*\\'" text))
       (not (member text '("t" "nil")))))

(defun themer-reader-form-palette-check (palette)
  "Each row of PALETTE, a list of (NAME-TEXT HEX-TEXT), as (NAME HEX PROBLEM).
NAME is a symbol, or nil if the text can't name an entry; HEX a lower-case
hex or nil; PROBLEM nil, or a string saying what is wrong with the row."
  (let (seen)
    (mapcar (pcase-lambda (`(,name ,hex))
              (let* ((ok (themer-reader-form-name-ok name))
                     (dup (and ok (member name seen)))
                     (hexp (themer-colour-hex-p hex)))
                (push name seen)
                (list (and ok (intern name)) (and hexp (downcase hex))
                      (cond ((string-empty-p name) "needs a name")
                            ((not ok) "not a usable name")
                            (dup "name used twice")
                            ((not hexp) "not a #rrggbb colour")))))
            palette)))

(defun themer-reader-form-state-palette (state)
  "Alist (NAME . HEX) of the usable palette entries of STATE."
  (cl-loop for (name hex problem) in (themer-reader-form-palette-check (plist-get state :palette))
           unless problem collect (cons name hex)))

(defun themer-reader-form-state-values (state)
  "Plist KEY -> value of STATE's slots, or :bad.
A value is a lower-case hex, a palette name (a symbol), or nil when empty."
  (let ((names (mapcar #'car (themer-reader-form-palette-check (plist-get state :palette)))))
    (cl-loop for k in (themer-reader-form--keys)
             for v = (string-trim (or (alist-get k (plist-get state :slots)) ""))
             append (list k (cond ((string-empty-p v) nil)
                                  ((themer-colour-hex-p v) (downcase v))
                                  ((and (themer-reader-form-name-ok v) (memq (intern v) names))
                                   (intern v))
                                  (t :bad))))))

(defun themer-reader-form-state-resolved (state)
  "Plist KEY -> hex of STATE's slots, palette names resolved; nil or :bad."
  (let ((pal (themer-reader-form-state-palette state)))
    (cl-loop for (k v) on (themer-reader-form-state-values state) by #'cddr
             append (list k (if (and v (symbolp v) (not (eq v :bad)))
                                (or (cdr (assq v pal)) :bad)
                              v)))))

(defun themer-reader-form-palette-users (state name)
  "The slot keys of STATE whose field names palette entry NAME (a string)."
  (when (themer-reader-form-name-ok name)
    (cl-loop for (k . v) in (plist-get state :slots)
             when (equal (string-trim v) name) collect k)))

(defun themer-reader-form--state-put (state key value)
  "A copy of STATE with KEY set to VALUE."
  (plist-put (copy-sequence state) key value))

(defun themer-reader-form-set-slot (state key text)
  "A copy of STATE with slot KEY's field set to TEXT."
  (themer-reader-form--state-put
   state :slots (mapcar (lambda (s) (if (eq (car s) key) (cons key text) s))
                        (plist-get state :slots))))

(defun themer-reader-form--check-new-name (state name)
  "Signal a `user-error' unless NAME can name a new entry of STATE."
  (unless (themer-reader-form-name-ok name)
    (user-error "%S can't name a palette entry" name))
  (when (assoc name (plist-get state :palette))
    (user-error "The palette already has %s" name)))

(defun themer-reader-form-palette-add (state name hex)
  "A copy of STATE with palette entry NAME, colour HEX, added at the end."
  (themer-reader-form--check-new-name state name)
  (unless (themer-colour-hex-p hex) (user-error "%S is not a #rrggbb colour" hex))
  (themer-reader-form--state-put state :palette
                                 (append (plist-get state :palette) (list (list name (downcase hex))))))

(defun themer-reader-form-palette-rename (state old new)
  "A copy of STATE with palette entry OLD renamed NEW, in every slot too."
  (unless (assoc old (plist-get state :palette)) (user-error "No palette entry %s" old))
  (themer-reader-form--check-new-name state new)
  (let ((users (themer-reader-form-palette-users state old)))
    (themer-reader-form--state-put
     (themer-reader-form--state-put
      state :palette (mapcar (lambda (e) (if (equal (car e) old) (cons new (cdr e)) e))
                             (plist-get state :palette)))
     :slots (mapcar (lambda (s) (if (memq (car s) users) (cons (car s) new) s))
                    (plist-get state :slots)))))

(defun themer-reader-form-palette-delete (state which &optional inline)
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
                  (themer-reader-form-palette-users state (car row)))))
    (when (and users (not inline))
      (user-error "%s is used by %s" (car row)
                  (mapconcat (lambda (k) (substring (symbol-name k) 1)) users ", ")))
    (themer-reader-form--state-put
     (themer-reader-form--state-put state :palette rest)
     :slots (mapcar (lambda (s) (if (memq (car s) users) (cons (car s) (cadr row)) s))
                    (plist-get state :slots)))))

(defun themer-reader-form-suggest-name (state hex)
  "A palette name for HEX not yet in STATE: its hue name, numbered if taken."
  (let* ((base (themer-reader-form--hue hex)) (name base) (i 1))
    (while (assoc name (plist-get state :palette))
      (setq i (1+ i) name (format "%s%d" base i)))
    name))

(defun themer-reader-form-pick-candidates (palette)
  "The Pick menu for PALETTE, an alist (NAME . HEX): an alist (TEXT . ACTION).
ACTION is the palette name (a symbol), `custom' or `add'."
  (append (mapcar (lambda (e) (cons (symbol-name (car e)) (car e))) palette)
          (list (cons themer-reader-form--custom 'custom)
                (cons themer-reader-form--add 'add))))

(defun themer-reader-form--pick-annotation (palette)
  "A completion annotation function for the Pick menu of PALETTE."
  (lambda (text)
    (if-let* ((hex (cdr (assoc text (mapcar (lambda (e) (cons (symbol-name (car e)) (cdr e))) palette)))))
        (concat "  " (propertize "    " 'face `(:background ,hex)) " " hex
                " " (propertize (themer-reader-form--hue hex) 'face 'shadow))
      "")))

(defun themer-reader-form-base16-state (state slots choices)
  "A copy of STATE with the base16 SLOTS as its palette, and CHOICES applied.
SLOTS is an alist (SLOT . HEX); CHOICES an alist KEY -> slot name, or nil
to empty the field.  Palette entries of STATE that slots not in CHOICES
still use are kept after the base16 ones."
  (let* ((state (cl-loop with st = state
                         for (k . slot) in choices
                         do (setq st (themer-reader-form-set-slot st k (or slot "")))
                         finally return st))
         (kept (cl-remove-if-not
                (lambda (e) (and (not (assoc (car e) slots))
                                 (themer-reader-form-palette-users state (car e))))
                (plist-get state :palette))))
    (themer-reader-form--state-put
     state :palette (append (mapcar (lambda (s) (list (car s) (cdr s))) slots) kept))))

;;;; Statuses (non-interactive)

(defun themer-reader-form--lc (hex bg)
  "APCA Lc of HEX on BG."
  (themer-colour-alc hex bg))

(defun themer-reader-form-statuses (derived)
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
            (funcall add :fg sev (format "fails Lc 45 (Lc %.1f)" (themer-reader-form--lc fg bg))))
           ((equal id "default-target")
            (funcall add :fg sev (format "Lc %.1f, below 60" (themer-reader-form--lc fg bg))))
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
                       (format "Lc %.1f, below 45" (themer-reader-form--lc hex bg)))))
           ((string-match "\\`loud-\\(.+\\)" id)
            (let ((hex (alist-get (intern (match-string 1 id)) loud)))
              (funcall add (intern (concat ":" (match-string 1 id))) sev
                       (format "fails Lc 35 (Lc %.1f)" (themer-reader-form--lc hex bg)))))
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
            (funcall add :accent sev (format "Lc %.1f, below 60" (themer-reader-form--lc (plist-get tiers :accent) bg))))
           ((equal id "accent-isearch")
            (funcall add :accent sev (format "isearch text on it: Lc %.1f, below 60"
                                             (abs (themer-reader-form--lc bg (plist-get tiers :accent))))))
           ((string-match "\\`\\(error\\|warning\\|added\\|removed\\)-" id)
            (let ((k (intern (concat ":" (match-string 1 id)))))
              (funcall add k sev (format "is %s" (themer-reader-form--hue (plist-get tiers k))))))))))
    ;; Shed families, and the Lc of the ones kept.
    (dolist (fam themer-reader-families)
      (let ((k (intern (format ":%s" fam))))
        (when (plist-get spec k)
          (if-let* ((hex (alist-get fam loud)))
              (unless (alist-get k out)
                (funcall add k 'ok (format "Lc %.1f" (themer-reader-form--lc hex bg))))
            (funcall add k 'should
                     (format "shed at %s: drawn as %s" (plist-get conf :level)
                             (car (alist-get fam themer-reader--fallbacks))))))))
    (unless (alist-get :fg out)
      (funcall add :fg 'ok (format "Lc %.1f" (themer-reader-form--lc fg bg))))
    (funcall add :bg 'ok (if (themer-colour-dark-p bg) "dark" "light"))
    (when (and (plist-get spec :binding) (not (alist-get :binding out)))
      (funcall add :binding 'ok (format "tint %s" (plist-get tiers :binding))))
    (when (and (plist-get spec :accent) (not (alist-get :accent out)))
      (funcall add :accent 'ok (format "Lc %.1f" (themer-reader-form--lc (plist-get tiers :accent) bg))))
    (dolist (k '(:popout :error :warning :added :removed))
      (when (and (plist-get spec k) (not (alist-get k out)))
        (funcall add k 'ok (themer-reader-form--hue (plist-get tiers k)))))
    (mapcar (lambda (x) (cons (car x) (reverse (cdr x)))) out)))

;;;; Samples

(defvar-local themer-reader-form--sample-buffer nil "The form's sample buffer.")
(defvar-local themer-reader-form--derived nil "The last derivation shown.")
(defvar-local themer-reader-form--model nil "The model the form was opened on.")

(defcustom themer-reader-form-sample-directory nil
  "Directory of your own samples, read as well as the package's samples/.
Each file named sample.EXT is a sample; its mode, as `auto-mode-alist'
and `major-mode-remap-alist' give it, names the language.  A file here
replaces the package's file of the same name.  nil means only the
package's samples."
  :type '(choice (const :tag "None" nil) directory)
  :group 'themer)

(defcustom themer-reader-form-sample-languages t
  "The languages whose samples the form shows when it opens.
t means all of them; otherwise a list of language symbols, named for
the sample's mode (`python', `emacs-lisp', ...).  The form's Samples
checkboxes change the choice for the rest of the session."
  :type '(choice (const :tag "All" t) (repeat symbol))
  :group 'themer)

(defconst themer-reader-form--language-names
  '((typescript . "TypeScript") (emacs-lisp . "Emacs Lisp"))
  "Display names of languages that `capitalize' gets wrong.")

(defvar themer-reader-form--selected :unset
  "The languages whose samples are shown, for this session.
:unset until the form changes it: then `themer-reader-form-sample-languages'.")

(defvar themer-reader-form--fontified (make-hash-table :test #'equal)
  "Fontified samples: (MODES TEXT FADE) -> (TEXT . RUNS), or :none.
RUNS is a list of (BEG END FACE).")

(defun themer-reader-form--language-name (lang)
  "The display name of sample language LANG."
  (or (alist-get lang themer-reader-form--language-names)
      (capitalize (symbol-name lang))))

(defun themer-reader-form--sample-file-modes (file)
  "The language of sample FILE and its candidate modes: (LANGUAGE MODE...).
The mode is FILE's in `auto-mode-alist', after `major-mode-remap-alist';
LANGUAGE is its name less -ts-mode, -mode or -ts-mode-maybe.  The
candidates are LANGUAGE-ts-mode, LANGUAGE-mode, then the mode itself:
the first usable one fontifies FILE.  nil if FILE has no mode."
  (when-let* ((mode (assoc-default file auto-mode-alist #'string-match))
              (mode (if (consp mode) (car mode) mode))
              ((symbolp mode)))
    (let* ((mode (or (alist-get mode major-mode-remap-alist) mode))
           (lang (replace-regexp-in-string "\\(-ts\\)?-mode\\(-maybe\\)?\\'" ""
                                           (symbol-name mode))))
      (cons (intern lang)
            (delete-dups
             (delq nil (list (intern-soft (concat lang "-ts-mode"))
                             (intern-soft (concat lang "-mode"))
                             (unless (string-suffix-p "-maybe" (symbol-name mode)) mode))))))))

(defun themer-reader-form--samples ()
  "The samples found: a list of (LANGUAGE (MODE...) . FILE), by name.
LANGUAGE and the modes are from `themer-reader-form--sample-file-modes';
a file with no mode is named for its extension, with no modes."
  (let (files)
    (dolist (dir (list (expand-file-name "samples/" themer-reader--library-directory)
                       themer-reader-form-sample-directory))
      (when (and dir (file-directory-p dir))
        (dolist (f (directory-files dir t "\\`sample\\.[^.]+\\'"))
          (setf (alist-get (file-name-nondirectory f) files nil nil #'equal) f))))
    (sort (mapcar (lambda (e)
                    (let ((lm (or (themer-reader-form--sample-file-modes (cdr e))
                                  (list (intern (file-name-extension (cdr e)))))))
                      (cons (car lm) (cons (cdr lm) (cdr e)))))
                  files)
          (lambda (a b) (string< (themer-reader-form--language-name (car a))
                                 (themer-reader-form--language-name (car b)))))))

(defun themer-reader-form--selected-languages ()
  "The languages shown, in the order of `themer-reader-form--samples'."
  (let ((sel (if (eq themer-reader-form--selected :unset)
                 themer-reader-form-sample-languages
               themer-reader-form--selected)))
    (cl-loop for (lang) in (themer-reader-form--samples)
             when (or (eq sel t) (memq lang sel)) collect lang)))

(defun themer-reader-form--sample-file-text (file)
  "The text of sample FILE, final newline dropped."
  (with-temp-buffer
    (insert-file-contents file)
    (string-remove-suffix "\n" (buffer-string))))

(defun themer-reader-form--mode-usable-p (mode)
  "Non-nil if major MODE exists, and its tree-sitter grammar if it has one."
  (and (fboundp mode)
       (let ((name (symbol-name mode)))
         (or (not (string-suffix-p "-ts-mode" name))
             (treesit-language-available-p (intern (string-remove-suffix "-ts-mode" name)))))))

(defun themer-reader-form--runs (string &optional prop)
  "STRING's runs of text property PROP (default `face'): a list of (BEG END VALUE)."
  (let ((prop (or prop 'face)) (pos 0) runs)
    (while (< pos (length string))
      (let ((next (next-single-property-change pos prop string (length string)))
            (v (get-text-property pos prop string)))
        (when v (push (list pos next v) runs))
        (setq pos next)))
    (nreverse runs)))

(defun themer-reader-form--sample-runs (modes text)
  "TEXT fontified by the first usable of MODES: (TEXT . RUNS), or :none.
RUNS is a list of (BEG END FACE), BEG and END 0-based string indices.
Tree-sitter buffers get `themer-reader-treesit-mode's rules, at
`treesit-font-lock-level' 4: calls and the like, which the standard
colours, are level-4 features."
  (let ((key (list modes text themer-reader-fade-commented-code)))
    (or (gethash key themer-reader-form--fontified)
        (puthash
         key
         (if-let* ((mode (cl-find-if #'themer-reader-form--mode-usable-p modes)))
             (with-temp-buffer
               (insert text)
               (let (runs)
                 (ignore-errors
                   ;; Around the install too: it recomputes the features.
                   (let ((treesit-font-lock-level 4))
                     (delay-mode-hooks (funcall mode))
                     (themer-reader--install)
                     (font-lock-mode 1)
                     (font-lock-ensure))
                   (setq runs (themer-reader-form--runs (buffer-string))))
                 (cons text runs)))
           :none)
         themer-reader-form--fontified))))

(defun themer-reader-form--face-attrs (face faces)
  "Attribute plist for FACE (a face or list of faces) from alist FACES."
  (let (attrs)
    (dolist (f (if (and (consp face) (not (keywordp (car face)))) face (list face)))
      (let ((a (if (symbolp f) (alist-get f faces) f)))
        (cl-loop for (k v) on a by #'cddr
                 unless (plist-member attrs k) do (setq attrs (plist-put attrs k v)))))
    attrs))

(defun themer-reader-form--sample-text (text runs faces fg bg)
  "TEXT with RUNS applied as text properties from FACES, on FG and BG."
  (let ((s (copy-sequence text)))
    (put-text-property 0 (length s) 'face `(:foreground ,fg :background ,bg) s)
    (pcase-dolist (`(,b ,e ,face) runs)
      (let ((a (themer-reader-form--face-attrs face faces)))
        (put-text-property b e 'face
                           (append (cl-loop for (k v) on a by #'cddr
                                            unless (memq k '(:foreground :background :height :box :inherit))
                                            append (list k v))
                                   `(:foreground ,(or (plist-get a :foreground) fg) :background ,bg))
                           s)))
    s))

(defun themer-reader-form-sample (derived &optional languages)
  "The samples of LANGUAGES as a string, fontified with DERIVED's faces.
LANGUAGES defaults to the selected ones.  The faces are text properties,
so the theme need not be enabled."
  (let* ((samples (themer-reader-form--samples))
         (languages (or languages (themer-reader-form--selected-languages)))
         (faces (themer-reader-faces derived))
         (tiers (plist-get derived :tiers))
         (bg (plist-get tiers :bg)) (fg (plist-get tiers :fg))
         (dim (or (plist-get tiers :dim) fg))
         (blocks
          (cl-loop
           for lang in languages
           for (modes . file) = (alist-get lang samples)
           when file
           collect (let* ((name (themer-reader-form--language-name lang))
                          (text (themer-reader-form--sample-file-text file))
                          (run (themer-reader-form--sample-runs modes text))
                          (tokens (and (consp run) (themer-reader-form--semtok-tokens file modes text)))
                          (run (if tokens
                                   (cons text (themer-reader-form--layer-tokens text (cdr run) tokens))
                                 run)))
                     (cons (propertize (format "── %s ──" name) 'face `(:foreground ,dim :background ,bg))
                           (if (eq run :none)
                               (propertize (format "(no major mode available for %s)" name)
                                           'face `(:foreground ,dim :background ,bg))
                             (themer-reader-form--sample-text (car run) (cdr run) faces fg bg))))))
         (width (+ 2 (cl-loop for (head . body) in blocks
                              maximize (max (length head)
                                            (cl-loop for l in (split-string body "\n") maximize (length l)))))))
    (if (null blocks)
        (propertize "No samples selected." 'face `(:foreground ,dim :background ,bg))
      (mapconcat
       (pcase-lambda (`(,head . ,body))
         (mapconcat (lambda (line)
                      (concat (propertize " " 'face `(:background ,bg)) line
                              (propertize (make-string (max 0 (- width (length line) 1)) ?\s)
                                          'face `(:background ,bg))))
                    (cons head (split-string body "\n")) "\n"))
       blocks "\n\n"))))

;;;; Semantic tokens
;;
;; Eglot paints semantic tokens in front of the font-lock faces, so the
;; samples get them too: the form visits a sample's file, connects eglot
;; without blocking, lets eglot paint, and reads the face lists eglot put
;; in the `eglot--semtok-faces' property.  A timer polls the pending
;; files and redraws the forms when tokens arrive.

(defcustom themer-reader-form-semantic-tokens t
  "Non-nil: layer eglot semantic tokens onto the samples, as eglot does.
Only for samples whose mode has an installed server in
`eglot-server-programs'.  The form visits the sample file and connects
eglot in the background, or uses a server already managing it; servers
and buffers it started go when the last form is killed."
  :type 'boolean
  :group 'themer)

(defcustom themer-reader-form-semantic-tokens-timeout 60
  "Seconds to wait for a sample's semantic tokens before giving up."
  :type 'number
  :group 'themer)

(defvar themer-reader-form--semtok (make-hash-table :test #'equal)
  "Semantic tokens per sample FILE -> plist.
:status is pending, done or none; :tokens a list of (BEG END FACES) over
:text; :buffer the visiting buffer, :created if the form visited it;
:started if the form started its server; :deadline when to give up.")

(defvar themer-reader-form--semtok-timer nil "Timer polling pending semantic tokens.")

(defun themer-reader-form--layer-tokens (text runs tokens)
  "RUNS over TEXT with semantic TOKENS layered on, as eglot paints them.
RUNS and TOKENS are lists of (BEG END FACE) and (BEG END FACES)."
  (let ((s (copy-sequence text)))
    (pcase-dolist (`(,b ,e ,face) runs)
      (put-text-property b e 'face face s))
    (pcase-dolist (`(,b ,e ,faces) tokens)
      (when (<= e (length s))
        (dolist (f faces) (add-face-text-property b e f nil s))))
    (themer-reader-form--runs s)))

(defun themer-reader-form--semtok-tokens (file modes text)
  "Semantic tokens for sample FILE if they are in and match TEXT, else nil.
Asks for them, in the background, when FILE has a server for MODES."
  (when themer-reader-form-semantic-tokens
    (let ((e (gethash file themer-reader-form--semtok)))
      (unless e
        (setq e (themer-reader-form--semtok-start file modes))
        (puthash file e themer-reader-form--semtok))
      (and (eq (plist-get e :status) 'done)
           (equal (plist-get e :text) text)
           (plist-get e :tokens)))))

(defun themer-reader-form--semtok-contact (mode)
  "Eglot's contact for MODE if its server is installed, else nil."
  (when-let* ((guess (cdr (ignore-errors (eglot--lookup-mode mode)))))
    (or (functionp guess)
        (not (stringp (car-safe guess)))
        (executable-find (car guess)))))

(defun themer-reader-form--semtok-start (file modes)
  "Start getting semantic tokens for sample FILE: its table entry.
MODES are the sample's candidate modes."
  (or (ignore-errors
        (when (and (require 'eglot nil t)
                   (cl-some #'themer-reader-form--semtok-contact
                            (cl-remove-if-not #'fboundp modes)))
          (let* ((existing (get-file-buffer file))
                 (buf (or existing (find-file-noselect file t)))
                 started)
            (with-current-buffer buf
              (unless (or (eglot-managed-p) (eglot-current-server))
                (when-let* ((contact (ignore-errors (eglot--guess-contact)))
                            (program (car-safe (nth 3 contact)))
                            ((or (not (stringp program)) (executable-find program))))
                  ;; Connects in the background: the server is registered,
                  ;; and the buffer managed, once it has initialised.
                  (let ((eglot-sync-connect nil))
                    (apply #'eglot contact))
                  (setq started t))))
            (if (or started (with-current-buffer buf (eglot-managed-p)))
                (progn
                  (themer-reader-form--semtok-schedule)
                  (list :status 'pending :buffer buf :created (not existing) :started started
                        :deadline (+ (float-time) themer-reader-form-semantic-tokens-timeout)))
              (unless existing (kill-buffer buf))
              nil))))
      (list :status 'none)))

(defun themer-reader-form--semtok-schedule ()
  "Start the polling timer if it isn't running."
  (unless (timerp themer-reader-form--semtok-timer)
    (setq themer-reader-form--semtok-timer
          (run-with-timer 0.5 0.5 #'themer-reader-form--semtok-poll))))

(defun themer-reader-form--semtok-harvest (buf)
  "BUF's text, final newline dropped, and eglot's tokens in it, or nil.
Tokens are (BEG END FACES), 0-based; nil until eglot has painted."
  (with-current-buffer buf
    (when (and (eglot-managed-p) (eglot-server-capable :semanticTokensProvider))
      (unless eglot-semantic-tokens-mode (eglot-semantic-tokens-mode 1))
      (save-restriction
        (widen)
        (font-lock-ensure)
        (when (plist-get eglot--semtok-state :data)
          (let ((s (buffer-string)))
            (cons (string-remove-suffix "\n" (substring-no-properties s))
                  (themer-reader-form--runs s 'eglot--semtok-faces))))))))

(defun themer-reader-form--semtok-poll ()
  "Collect the semantic tokens that have arrived; redraw the forms if any did."
  (let (changed pending)
    (maphash
     (lambda (_file e)
       (when (eq (plist-get e :status) 'pending)
         (let* ((buf (plist-get e :buffer))
                (got (condition-case err
                         (and (buffer-live-p buf) (themer-reader-form--semtok-harvest buf))
                       (error (message "themer: semantic tokens: %s" (error-message-string err))
                              (plist-put e :status 'none)
                              nil))))
           (cond (got (plist-put e :status 'done)
                      (plist-put e :text (car got))
                      (plist-put e :tokens (cdr got))
                      (setq changed t))
                 ((or (not (buffer-live-p buf)) (> (float-time) (plist-get e :deadline)))
                  (plist-put e :status 'none))
                 ((eq (plist-get e :status) 'pending) (setq pending t))))))
     themer-reader-form--semtok)
    (unless pending
      (cancel-timer themer-reader-form--semtok-timer)
      (setq themer-reader-form--semtok-timer nil))
    (when changed
      (dolist (b (buffer-list))
        (with-current-buffer b
          (when (derived-mode-p 'themer-reader-form-mode)
            (themer-reader-form--update-samples)))))))

(defun themer-reader-form--semtok-stop ()
  "Shut down the servers and kill the buffers the forms started."
  (when (timerp themer-reader-form--semtok-timer)
    (cancel-timer themer-reader-form--semtok-timer))
  (setq themer-reader-form--semtok-timer nil)
  (maphash
   (lambda (_file e)
     (let* ((buf (plist-get e :buffer))
            (server (and (plist-get e :started) (buffer-live-p buf)
                         (with-current-buffer buf (eglot-current-server)))))
       (when (and server (cl-every (lambda (b) (eq b buf)) (eglot--managed-buffers server)))
         (ignore-errors (eglot-shutdown server)))
       (when (and (plist-get e :created) (buffer-live-p buf) (not (buffer-modified-p buf)))
         (kill-buffer buf))))
   themer-reader-form--semtok)
  (clrhash themer-reader-form--semtok))

;;;; The sample buffer

(defvar-local themer-reader-form--sample-owner nil
  "In a sample buffer: the form buffer it shows samples for.")

(defvar-keymap themer-reader-form-sample-mode-map
  :parent special-mode-map
  "g" #'themer-reader-form-sample-refresh
  "q" #'quit-window)

(define-derived-mode themer-reader-form-sample-mode special-mode "Reader-Sample"
  "Read-only buffer of code samples drawn with a reader theme form's colours.
\\{themer-reader-form-sample-mode-map}"
  (setq truncate-lines t)
  (setq-local revert-buffer-function (lambda (&rest _) (themer-reader-form-sample-refresh))))

(defun themer-reader-form--sample-buffer-name (name)
  "The name of the sample buffer for the theme called NAME."
  (format "*themer-reader-sample: %s*" (or name "new")))

(defun themer-reader-form--update-samples (&optional derived)
  "Redraw the sample buffer from DERIVED (default: the last derivation).
Windows showing it keep their point and scroll."
  (let ((buf themer-reader-form--sample-buffer)
        (derived (or derived themer-reader-form--derived)))
    (when (and derived (buffer-live-p buf))
      (let ((text (themer-reader-form-sample derived))
            (tiers (plist-get derived :tiers)))
        (with-current-buffer buf
          (let ((inhibit-read-only t)
                (pt (point))
                (wins (mapcar (lambda (w) (list w (window-point w) (window-start w)))
                              (get-buffer-window-list buf nil t))))
            (erase-buffer)
            (insert text)
            (setq-local face-remapping-alist
                        `((default :foreground ,(plist-get tiers :fg) :background ,(plist-get tiers :bg))))
            (goto-char (min pt (point-max)))
            (pcase-dolist (`(,w ,p ,s) wins)
              (set-window-point w (min p (point-max)))
              (set-window-start w (min s (point-max)) t))
            (set-buffer-modified-p nil)))))))

(defun themer-reader-form--ensure-sample-buffer ()
  "The form's sample buffer, made (and filled) if it isn't live."
  (unless (buffer-live-p themer-reader-form--sample-buffer)
    (let ((form (current-buffer)))
      (setq themer-reader-form--sample-buffer
            (generate-new-buffer
             (themer-reader-form--sample-buffer-name (plist-get themer-reader-form--model :name))))
      (with-current-buffer themer-reader-form--sample-buffer
        (themer-reader-form-sample-mode)
        (setq themer-reader-form--sample-owner form)
        (let ((inhibit-read-only t))
          (insert (propertize "Deriving..." 'face 'shadow))))
      (themer-reader-form--update-samples)))
  themer-reader-form--sample-buffer)

(defconst themer-reader-form--sample-width 120
  "Columns for the sample window when it sits beside the form.")

(defconst themer-reader-form--form-min-width 100
  "Columns the form keeps when the samples are split off to its right.")

(defun themer-reader-form-show-samples ()
  "Show the sample buffer beside the form.
The samples split the form's window: to the right if it is wide enough
for both, else below.  `display-buffer-alist' takes precedence."
  (interactive)
  (let* ((buf (themer-reader-form--ensure-sample-buffer))
         (win (or (get-buffer-window (current-buffer)) (selected-window)))
         (wide (>= (window-total-width win)
                   (+ themer-reader-form--form-min-width
                      themer-reader-form--sample-width 1))))
    (display-buffer
     buf `((display-buffer-reuse-window display-buffer-in-direction)
           (direction . ,(if wide 'right 'below))
           (window . ,win)
           (window-width . ,(1+ themer-reader-form--sample-width))))))

(defun themer-reader-form-sample-refresh ()
  "Redraw the samples from the form's last derivation."
  (interactive)
  (if (buffer-live-p themer-reader-form--sample-owner)
      (with-current-buffer themer-reader-form--sample-owner
        (themer-reader-form--update-samples))
    (user-error "The form is gone")))

(defun themer-reader-form-set-sample-languages (languages)
  "Show the samples of LANGUAGES, and redraw the sample buffer now."
  (setq themer-reader-form--selected languages)
  (themer-reader-form--update-samples))

(defun themer-reader-form--kill-samples ()
  "Close and kill this form's sample buffer."
  (when-let* ((buf themer-reader-form--sample-buffer)
              ((buffer-live-p buf)))
    (dolist (w (get-buffer-window-list buf nil t))
      (ignore-errors (quit-window t w)))
    (when (buffer-live-p buf) (kill-buffer buf))))

;;;; The form buffer

(defvar-local themer-reader-form--widgets nil "Alist KEY -> field widget.")
(defvar-local themer-reader-form--overlays nil "Alist KEY -> swatch/status overlay.")
(defvar-local themer-reader-form--palette-rows nil
  "The palette rows in order, each a plist (:name WIDGET :hex WIDGET :overlay OV).
The name widget's :themer-name is the name the slots know the entry by.")
(defvar-local themer-reader-form--dynamic nil "Marker where the derived sections start.")
(defvar-local themer-reader-form--timer nil)
(defvar-local themer-reader-form--apply-widget nil)
(defvar-local themer-reader-form--samples-widget nil "The Samples checklist widget.")
(defvar-local themer-reader-form--applied nil
  "Non-nil while Apply is on: plist (:themes PRIOR :rules RULES-MODE-WAS-ON).")

(defconst themer-reader-form--preview-theme 'themer-reader-form-preview
  "The theme Apply enables.")

(defvar-keymap themer-reader-form-mode-map
  :parent widget-keymap
  "C-c C-c" #'themer-reader-form-save
  "C-c C-k" #'themer-reader-form-cancel)

(defvar-keymap themer-reader-form-field-map
  :parent widget-field-keymap
  "C-c C-c" #'themer-reader-form-save
  "C-c C-k" #'themer-reader-form-cancel
  "C-c C-a" #'themer-picker-adjust)

(define-derived-mode themer-reader-form-mode nil "Reader-Theme"
  "Form for a reader theme.
\\{themer-reader-form-mode-map}"
  (setq-local font-lock-defaults nil)
  (setq truncate-lines t))

(defun themer-reader-form--value (key)
  "The trimmed text of field KEY."
  (when-let* ((w (alist-get key themer-reader-form--widgets)))
    (string-trim (widget-value w))))

(defun themer-reader-form--state ()
  "The form's fields as a state (see the Model commentary)."
  (list :name (or (themer-reader-form--value :name) "")
        :doc (or (themer-reader-form--value :doc) "")
        :palette (mapcar (lambda (row)
                           (list (string-trim (widget-value (plist-get row :name)))
                                 (string-trim (widget-value (plist-get row :hex)))))
                         themer-reader-form--palette-rows)
        :slots (mapcar (lambda (k) (cons k (or (themer-reader-form--value k) "")))
                       (themer-reader-form--keys))))

(defun themer-reader-form--values ()
  "Plist of the form's slots: hex, palette name, nil when empty, or :bad."
  (themer-reader-form-state-values (themer-reader-form--state)))

(defun themer-reader-form-state-model (state model)
  "MODEL with the name, doc and spec of form STATE.
Signal a `user-error' if a field can't be saved."
  (cl-loop for (text) in (plist-get state :palette)
           for row in (themer-reader-form-palette-check (plist-get state :palette))
           when (nth 2 row) do (user-error "Palette entry %S: %s" text (nth 2 row)))
  (let ((vals (themer-reader-form-state-values state))
        (name (plist-get state :name)))
    (cl-loop for (k v) on vals by #'cddr
             when (eq v :bad) do (user-error "%s is not a #rrggbb colour or palette name" k))
    (when (string-empty-p name) (user-error "The theme needs a name"))
    (let ((pal (mapcar (lambda (e) (list (car e) (cdr e))) (themer-reader-form-state-palette state))))
      (plist-put (plist-put (plist-put (copy-sequence model) :name (intern name))
                            :doc (plist-get state :doc))
                 :spec (themer-reader-form--merge-spec (plist-get model :spec)
                                                       (append (list :palette pal) vals))))))

(defun themer-reader-form-model ()
  "The model of the form as edited."
  (themer-reader-form-state-model (themer-reader-form--state) themer-reader-form--model))

(defun themer-reader-form--swatch (hex bg &optional bold)
  "A swatch for HEX on BG: a block and sample text, BOLD if non-nil."
  (concat (propertize "  " 'face `(:background ,hex))
          (propertize " Abc " 'face `(:foreground ,hex :background ,bg
                                                  :weight ,(if bold 'bold 'normal)))))

(defun themer-reader-form--status-string (items)
  "Status ITEMS, a list of (SEVERITY . TEXT), as one string."
  (mapconcat (pcase-lambda (`(,sev . ,text))
               (propertize text 'face (pcase sev ('must 'error) ('should 'warning) (_ 'shadow))))
             items "; "))

(defun themer-reader-form--update-swatches (derived)
  "Repaint swatches and statuses from the fields and DERIVED (may be nil)."
  (let* ((state (themer-reader-form--state))
         (vals (themer-reader-form-state-values state))
         (hexes (themer-reader-form-state-resolved state))
         (tiers (plist-get derived :tiers))
         (bg (or (and (stringp (plist-get hexes :bg)) (plist-get hexes :bg))
                 (plist-get tiers :bg)
                 (themer-reader-form--to-hex (face-background 'default nil t))
                 "#000000"))
         (statuses (and derived (themer-reader-form-statuses derived))))
    ;; Palette rows
    (cl-loop for row in themer-reader-form--palette-rows
             for (name hex problem) in (themer-reader-form-palette-check (plist-get state :palette))
             for users = (and name (themer-reader-form-palette-users state (symbol-name name)))
             do (overlay-put
                 (plist-get row :overlay) 'after-string
                 (concat (if hex (themer-reader-form--swatch hex bg) (make-string 7 ?\s)) "  "
                         (if hex
                             (format "%-7s Lc %5.1f  " (themer-reader-form--hue hex)
                                     (themer-reader-form--lc hex bg))
                           (make-string 18 ?\s))
                         (cond (problem (propertize problem 'face 'error))
                               (users (mapconcat (lambda (k) (substring (symbol-name k) 1)) users ", "))
                               (t (propertize "(unused)" 'face 'shadow))))))
    ;; Slots
    (pcase-dolist (`(,key ,_label ,_section ,required ,note) themer-reader-form--fields)
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
                                   (themer-reader-form--status-string (alist-get key statuses))
                                 ""))))))
        (when-let* ((ov (alist-get key themer-reader-form--overlays)))
          (overlay-put ov 'after-string
                       (concat (if shown (themer-reader-form--swatch shown bg) (make-string 7 ?\s))
                               "  " (propertize (format "%-34s" note) 'face 'shadow)
                               status)))))))

(defun themer-reader-form--insert-tiers (derived)
  "Insert the derived tiers of DERIVED."
  (let* ((tiers (plist-get derived :tiers))
         (bg (plist-get tiers :bg))
         (cell (lambda (hex &optional bold)
                 (if hex
                     (format "%s %s %4.1f" (themer-reader-form--swatch hex bg bold) hex
                             (themer-reader-form--lc hex bg))
                   (format "%-20s" "-")))))
    (widget-insert (propertize "Derived tiers" 'face 'bold) "  (swatch, hex, Lc)\n")
    (insert (format "  %-12s %-20s  %-20s  %-20s  %-20s\n" "" "recessive" "quiet" "loud" "strong"))
    (dolist (fam themer-reader-families)
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

(defun themer-reader-form--insert-conformance (derived)
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

(defun themer-reader-form--update-dynamic (derived &optional message)
  "Redraw the sections after the fields from DERIVED, or show MESSAGE."
  (let ((inhibit-read-only t) (inhibit-modification-hooks t))
    (save-excursion
      (delete-region themer-reader-form--dynamic (point-max))
      (goto-char themer-reader-form--dynamic)
      (if (not derived)
          (insert (propertize (or message "") 'face 'shadow) "\n")
        (themer-reader-form--insert-tiers derived)
        (insert "\n")
        (themer-reader-form--insert-conformance derived)))))

(defun themer-reader-form-refresh (&optional buffer interruptible)
  "Re-derive the form in BUFFER if a colour changed, and redraw.
With INTERRUPTIBLE, input aborts the derivation and reschedules it."
  (let ((buffer (or buffer (current-buffer))))
    (when (buffer-live-p buffer)
      (with-current-buffer buffer
        (let* ((state (themer-reader-form--state))
               (vals (themer-reader-form-state-resolved state))
               (bad (append
                     (cl-loop for (name _ problem) in (themer-reader-form-palette-check
                                                       (plist-get state :palette))
                              for (text) in (plist-get state :palette)
                              when problem collect (if name (symbol-name name)
                                                     (format "palette entry %S" text)))
                     (cl-loop for (k v) on vals by #'cddr
                              when (or (eq v :bad)
                                       (and (null v) (nth 3 (assq k themer-reader-form--fields))))
                              collect (substring (symbol-name k) 1))))
               (spec (cl-loop for (k v) on vals by #'cddr when (stringp v) append (list k v))))
          (cond
           (bad
            (themer-reader-form--update-swatches nil)
            (themer-reader-form--update-dynamic
             nil (format "Fix %s to derive the theme." (string-join bad ", "))))
           ((equal spec (plist-get themer-reader-form--derived :spec))
            (themer-reader-form--update-swatches themer-reader-form--derived))
           (t
            (let ((d (if interruptible
                         (while-no-input (redisplay) (themer-reader-derive spec))
                       (themer-reader-derive spec))))
              (if (eq d t)
                  (themer-reader-form--schedule)  ; interrupted by input
                (setq themer-reader-form--derived d)
                (themer-reader-form--update-swatches d)
                (themer-reader-form--update-dynamic d)
                (themer-reader-form--update-samples d)
                (when themer-reader-form--applied
                  (themer-reader-form--define-preview d)))))))))))

(defun themer-reader-form--schedule (&rest _)
  "Refresh the form after `themer-preview-delay' idle seconds."
  (when (timerp themer-reader-form--timer)
    (cancel-timer themer-reader-form--timer))
  (setq themer-reader-form--timer
        (run-with-idle-timer (if (boundp 'themer-preview-delay) themer-preview-delay 0.4)
                             nil #'themer-reader-form-refresh (current-buffer) t)))

;;;; Apply

(defun themer-reader-form--define-preview (derived)
  "Set the preview theme's faces from DERIVED and enable it."
  (let ((th themer-reader-form--preview-theme))
    (unless (custom-theme-p th)
      (custom-declare-theme th nil "Preview of a reader theme form."))
    (put th 'theme-settings nil)
    (themer-reader-define th (plist-get derived :spec))
    (enable-theme th)))

(defun themer-reader-form--apply (on)
  "Turn Apply ON or off."
  (cond
   ((and on (not themer-reader-form--applied))
    (unless themer-reader-form--derived
      (user-error "Fix the colours first"))
    (setq themer-reader-form--applied
          (list :themes custom-enabled-themes :rules themer-reader-treesit-mode))
    (mapc #'disable-theme custom-enabled-themes)
    (themer-reader-form--define-preview themer-reader-form--derived))
   ((and (not on) themer-reader-form--applied)
    (let ((prior themer-reader-form--applied)
          (th themer-reader-form--preview-theme))
      (setq themer-reader-form--applied nil)
      (when (custom-theme-p th)
        (disable-theme th)
        (put th 'theme-settings nil)
        (setq custom-known-themes (delq th custom-known-themes)))
      (dolist (x (reverse (plist-get prior :themes)))
        (enable-theme x))
      (unless (eq (and themer-reader-treesit-mode t) (and (plist-get prior :rules) t))
        (themer-reader-treesit-mode (if (plist-get prior :rules) 1 -1)))))))

(defun themer-reader-form--cleanup ()
  "Undo Apply and stop the timer: for `kill-buffer-hook'."
  (when (timerp themer-reader-form--timer)
    (cancel-timer themer-reader-form--timer))
  (themer-reader-form--apply nil)
  (themer-reader-form--kill-samples)
  (unless (cl-some (lambda (b) (and (not (eq b (current-buffer)))
                                    (eq (buffer-local-value 'major-mode b) 'themer-reader-form-mode)))
                   (buffer-list))
    (themer-reader-form--semtok-stop)))

;;;; Building the form

(defun themer-reader-form--button (label fn)
  "Insert a push button LABEL calling FN with no arguments."
  (widget-create 'push-button :notify (lambda (&rest _) (funcall fn)) label))

(defun themer-reader-form--field (key value size)
  "Insert an editable field for KEY with VALUE and SIZE."
  (let ((w (widget-create 'editable-field :size size :format "%v" :value (or value "")
                          :keymap themer-reader-form-field-map
                          :notify #'themer-reader-form--schedule)))
    (push (cons key w) themer-reader-form--widgets)
    w))

(defun themer-reader-form--palette-row (name hex)
  "Insert a palette row for entry NAME with colour HEX, and return it."
  (let* ((nw (widget-create 'editable-field :size 14 :format "%v" :value name
                            :keymap themer-reader-form-field-map
                            :themer-name name
                            :notify #'themer-reader-form--name-notify))
         (_ (widget-insert " "))
         (hw (widget-create 'editable-field :size 8 :format "%v" :value hex
                            :keymap themer-reader-form-field-map
                            :notify #'themer-reader-form--schedule))
         (row (list :name nw :hex hw)))
    (widget-insert " ")
    (themer-reader-form--button "Pick" (lambda () (themer-reader-form--palette-pick row)))
    (widget-insert " ")
    (themer-reader-form--button "Rename" (lambda () (themer-reader-form-palette-rename-entry row)))
    (widget-insert " ")
    (themer-reader-form--button "Delete" (lambda () (themer-reader-form-palette-delete-entry row)))
    (widget-insert " ")
    (plist-put row :overlay (make-overlay (1- (point)) (point)))))

(defun themer-reader-form--render (model &optional state)
  "Draw the form for MODEL in the current buffer.
The fields show STATE, a form state, if given, else MODEL."
  (let ((applied themer-reader-form--applied)
        (samples themer-reader-form--sample-buffer))
    (themer-reader-form-mode)
    (setq themer-reader-form--applied applied
          themer-reader-form--sample-buffer samples))
  (let ((inhibit-read-only t)) (erase-buffer))
  (remove-overlays)
  (add-hook 'kill-buffer-hook #'themer-reader-form--cleanup nil t)
  (setq themer-reader-form--model model
        themer-reader-form--widgets nil
        themer-reader-form--overlays nil
        themer-reader-form--palette-rows nil
        themer-reader-form--derived nil)
  (let ((state (or state (themer-reader-form-model-state model))))
    (widget-insert (propertize "Reader theme" 'face 'bold)
                   (if-let* ((f (plist-get model :file))) (format "  %s" (abbreviate-file-name f)) "  (new)")
                   "\n\n")
    (themer-reader-form--button "Save" #'themer-reader-form-save) (widget-insert " ")
    (themer-reader-form--button "Export standalone" #'themer-reader-form-export) (widget-insert " ")
    (themer-reader-form--button "Import base16" #'themer-reader-form-import-base16) (widget-insert " ")
    (themer-reader-form--button "Revert" #'themer-reader-form-revert) (widget-insert " ")
    (themer-reader-form--button "Check" #'themer-reader-form-check) (widget-insert "  ")
    (setq themer-reader-form--apply-widget
          (widget-create 'checkbox :notify (lambda (w &rest _)
                                             (condition-case err
                                                 (themer-reader-form--apply (widget-value w))
                                               (user-error (widget-value-set w nil)
                                                           (message "%s" (error-message-string err)))))
                         (and themer-reader-form--applied t)))
    (widget-insert " Apply (preview globally)\n\n")
    (widget-insert (format "  %-11s " "Name"))
    (themer-reader-form--field :name (plist-get state :name) 30)
    (widget-insert "\n" (format "  %-11s " "Description"))
    (themer-reader-form--field :doc (plist-get state :doc) 60)
    (widget-insert "\n\n" (propertize "Palette" 'face 'bold)
                   "  (named colours; a slot takes a name or a hex)\n")
    (dolist (e (plist-get state :palette))
      (widget-insert "  ")
      (push (themer-reader-form--palette-row (car e) (cadr e)) themer-reader-form--palette-rows)
      (widget-insert "\n"))
    (setq themer-reader-form--palette-rows (nreverse themer-reader-form--palette-rows))
    (widget-insert "  ")
    (themer-reader-form--button "Add" #'themer-reader-form-palette-add-entry)
    (widget-insert "\n")
    (let (section)
      (pcase-dolist (`(,key ,label ,sec ,required ,_note) themer-reader-form--fields)
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
        (themer-reader-form--field key (alist-get key (plist-get state :slots)) 14)
        (widget-insert " ")
        (themer-reader-form--button "Pick" (lambda () (themer-reader-form-pick key)))
        (widget-insert " ")
        (let ((ov (make-overlay (1- (point)) (point))))
          (push (cons key ov) themer-reader-form--overlays))
        (widget-insert "\n")))
    (widget-insert "\n" (propertize "Samples" 'face 'bold) "  (shown in their own buffer)  ")
    (themer-reader-form--button "Show samples" #'themer-reader-form-show-samples)
    (widget-insert "\n  ")
    (setq themer-reader-form--samples-widget
          (apply #'widget-create 'checklist
                 :value (themer-reader-form--selected-languages)
                 :entry-format "%b %v   "
                 :notify (lambda (w &rest _)
                           (themer-reader-form-set-sample-languages (widget-value w)))
                 (mapcar (lambda (e)
                           `(item :tag ,(themer-reader-form--language-name (car e))
                                  :format "%t" :value ,(car e)))
                         (themer-reader-form--samples))))
    (widget-insert "\n\n")
    (setq themer-reader-form--dynamic (point-marker))
    (widget-insert "\n"))
  (use-local-map themer-reader-form-mode-map)
  (widget-setup)
  (themer-reader-form--update-swatches nil)
  (themer-reader-form--update-dynamic nil "Deriving...")
  (goto-char (point-min))
  (widget-forward 1))

(defun themer-reader-form--rerender (state &optional goto)
  "Redraw the form with STATE and re-derive, keeping point's line and column.
With GOTO, a function, call it afterwards to place point."
  (let ((line (line-number-at-pos)) (col (current-column)))
    (themer-reader-form--render themer-reader-form--model state)
    (goto-char (point-min))
    (forward-line (1- line))
    (move-to-column col)
    (when goto (funcall goto))
    (themer-reader-form-refresh)))

(defun themer-reader-form--open (model)
  "Open a form buffer for MODEL and return it."
  (let ((buf (generate-new-buffer (format "*reader-theme %s*" (or (plist-get model :name) "new")))))
    (with-current-buffer buf
      (themer-reader-form--render model)
      (setq themer-reader-form--timer
            (run-with-timer 0 nil #'themer-reader-form-refresh buf t)))
    ;; The selected window, not a new split, so the form keeps the room it
    ;; had and the samples are split off it.
    (pop-to-buffer-same-window buf)
    (with-current-buffer buf (themer-reader-form-show-samples))
    buf))

;;;; Commands

(defun themer-reader-form--seed-model (seed)
  "A new model seeded from SEED: a theme file, a spec plist, or nil."
  (let ((m (cond ((stringp seed) (themer-reader-form-read-file seed))
                 (seed (list :spec seed)))))
    (list :name (and (plist-get m :name) (intern (format "%s-copy" (plist-get m :name))))
          :doc (or (plist-get m :doc) "")
          :spec (or (plist-get m :spec)
                    (let ((bg (themer-reader-form--to-hex (face-background 'default nil t)))
                          (fg (themer-reader-form--to-hex (face-foreground 'default nil t))))
                      (and bg fg (list :palette `((bg ,bg) (fg ,fg)) :bg 'bg :fg 'fg)))))))

;;;###autoload
(defun themer-reader-new-theme (&optional seed)
  "Open a form for a new reader theme, seeded from SEED.
SEED is a reader theme file or a spec plist; interactively, a theme
chosen by name (empty for a form with only the current colours)."
  (interactive (list (themer-reader-form--read-theme-file "Seed from theme (empty for none): ")))
  (themer-reader-form--open (themer-reader-form--seed-model seed)))

;;;###autoload
(defun themer-reader-edit-theme (&optional file)
  "Open a form on reader theme FILE.
Interactively, this buffer's theme file if it has a reader theme, else
one chosen by name from `custom-theme-load-path' and
`themer-reader-theme-directory'."
  (interactive
   (list (or (and buffer-file-name (themer-reader-form--deftheme-bounds) buffer-file-name)
             (themer-reader-form--read-theme-file "Edit reader theme: ")
             (user-error "No theme chosen"))))
  (themer-reader-form--open
   (if-let* ((buf (get-file-buffer file))
             ((with-current-buffer buf (themer-reader-form--deftheme-bounds))))
       (with-current-buffer buf (themer-reader-form-parse (buffer-string) (expand-file-name file)))
     (themer-reader-form-read-file file))))

(defun themer-reader-form-save (&optional file)
  "Save the form's theme to FILE.
FILE defaults to the edited file (renamed with the theme), else
`themer-reader-theme-directory'.  With a prefix argument, ask."
  (interactive
   (list (when current-prefix-arg
           (read-file-name "Save theme to: " nil nil nil
                           (format "%s-theme.el" (themer-reader-form--value :name))))))
  (let* ((model (themer-reader-form-model))
         (file (expand-file-name (or file (themer-reader-form--default-file model)))))
    (when (and (file-exists-p file)
               (not (equal file (plist-get model :file)))
               (called-interactively-p 'any)
               (not (y-or-n-p (format "%s exists; overwrite? " file))))
      (user-error "Not saved"))
    (let ((new (themer-reader-form-write model file)))
      (setq themer-reader-form--model new)
      ;; A theme saved anywhere becomes loadable in this session.
      (themer-reader-add-theme-directory (file-name-directory file))
      (when-let* ((buf (get-file-buffer file))
                  ((not (buffer-modified-p buf))))
        (with-current-buffer buf (revert-buffer t t t)))
      (rename-buffer (format "*reader-theme %s*" (plist-get new :name)) t)
      (when (buffer-live-p themer-reader-form--sample-buffer)
        (with-current-buffer themer-reader-form--sample-buffer
          (rename-buffer (themer-reader-form--sample-buffer-name (plist-get new :name)) t)))
      (message "Wrote %s" file)
      file)))

(defun themer-reader-form-cancel ()
  "Kill the form, asking first if it has unsaved changes."
  (interactive)
  (when (or (not (called-interactively-p 'any))
            (equal (ignore-errors (themer-reader-form-source (themer-reader-form-model)))
                   (ignore-errors (themer-reader-form-source themer-reader-form--model)))
            (y-or-n-p "Discard unsaved changes? "))
    (let ((buf (current-buffer)))
      (quit-window nil)
      (kill-buffer buf))))

(defun themer-reader-form-revert ()
  "Put the form back to the model it was opened on, or last saved."
  (interactive)
  (let ((m themer-reader-form--model))
    (themer-reader-form--render
     (if-let* ((f (plist-get m :file)) ((file-exists-p f))) (themer-reader-form-read-file f) m))
    (themer-reader-form-refresh)))

(defun themer-reader-form-check ()
  "Show the full conformance report for the form's theme."
  (interactive)
  (themer-reader-form-refresh)
  (unless themer-reader-form--derived (user-error "Fix the colours first"))
  (let ((name (themer-reader-form--value :name)) (d themer-reader-form--derived))
    (with-help-window "*themer-reader-check*"
      (with-current-buffer standard-output
        (themer-reader-report name d)))))

(defun themer-reader-form-export (&optional file)
  "Export the form's theme to FILE as a standalone theme."
  (interactive)
  (let* ((m (themer-reader-form-model))
         (file (or file (read-file-name "Export theme to: " nil nil nil
                                        (format "%s-theme.el" (plist-get m :name))))))
    (themer-reader-export file nil (plist-get m :name) (plist-get m :spec))))

(defun themer-reader-form--set (key text)
  "Set slot field KEY to TEXT: a hex or a palette name."
  (widget-value-set (alist-get key themer-reader-form--widgets) (or text ""))
  (widget-setup))

(defun themer-reader-form--read-hex (prompt)
  "Read a colour with `read-color' and PROMPT, as a lower-case hex."
  (let* ((c (read-color prompt))
         (hex (themer-reader-form--to-hex c)))
    (or hex (user-error "Unknown colour %s" c))))

(defun themer-reader-form-read-pick (prompt palette &optional current)
  "Read a slot's colour with PROMPT from the Pick menu of PALETTE.
PALETTE is an alist (NAME . HEX); CURRENT the field's text, the default.
Return a palette name (a symbol), a hex typed in, `custom' or `add'."
  (let* ((cands (themer-reader-form-pick-candidates palette))
         (table (lambda (str pred action)
                  (if (eq action 'metadata)
                      `(metadata (category . themer-palette)
                                 (display-sort-function . identity)
                                 (annotation-function
                                  . ,(themer-reader-form--pick-annotation palette)))
                    (complete-with-action action cands str pred))))
         (choice (string-trim (completing-read prompt table nil nil nil nil
                                               (and current (not (string-empty-p current)) current)))))
    (cond ((assoc choice cands) (cdr (assoc choice cands)))
          ((themer-colour-hex-p choice) (downcase choice))
          ((string-empty-p choice) (user-error "No colour chosen"))
          (t (user-error "%s is not a palette entry or #rrggbb colour" choice)))))

(defun themer-reader-form-pick (key)
  "Choose the colour of slot KEY from a menu of the palette entries.
The menu also has \"Custom hex…\" (`read-color') and \"Add to palette…\"
\(a new entry, which the slot then names)."
  (interactive (list (intern (completing-read "Field: " (mapcar #'car themer-reader-form--fields)))))
  (let* ((state (themer-reader-form--state))
         (label (nth 1 (assq key themer-reader-form--fields)))
         (choice (themer-reader-form-read-pick (format "%s: " label)
                                               (themer-reader-form-state-palette state)
                                               (alist-get key (plist-get state :slots)))))
    (pcase choice
      ('custom
       (themer-reader-form--set key (themer-reader-form--read-hex (format "%s (name or #rrggbb): " label)))
       (themer-reader-form--schedule))
      ('add
       (let* ((hex (themer-reader-form--read-hex "New palette colour (name or #rrggbb): "))
              (def (themer-reader-form-suggest-name state hex))
              (name (string-trim (read-string (format "Name for %s (default %s): " hex def) nil nil def))))
         (themer-reader-form--rerender
          (themer-reader-form-set-slot (themer-reader-form-palette-add state name hex) key name))))
      ((pred symbolp)
       (themer-reader-form--set key (symbol-name choice))
       (themer-reader-form--schedule))
      (_
       (themer-reader-form--set key choice)
       (themer-reader-form--schedule)))))

(defun themer-reader-form--row-name (row)
  "The text of palette ROW's name field."
  (string-trim (widget-value (plist-get row :name))))

(defun themer-reader-form--palette-pick (row)
  "Pick the colour of palette ROW with `read-color'."
  (let ((hex (themer-reader-form--read-hex
              (format "Colour of %s (name or #rrggbb): " (themer-reader-form--row-name row)))))
    (widget-value-set (plist-get row :hex) hex)
    (widget-setup)
    (themer-reader-form--schedule)))

(defun themer-reader-form--goto-row (index)
  "Move point to the name field of palette row INDEX."
  (when-let* ((row (nth index themer-reader-form--palette-rows)))
    (goto-char (widget-field-start (plist-get row :name)))))

(defun themer-reader-form-palette-add-entry ()
  "Add a palette entry: read its colour and name."
  (interactive)
  (let* ((state (themer-reader-form--state))
         (hex (themer-reader-form--read-hex "New palette colour (name or #rrggbb): "))
         (def (themer-reader-form-suggest-name state hex))
         (name (string-trim (read-string (format "Name for %s (default %s): " hex def) nil nil def)))
         (new (themer-reader-form-palette-add state name hex)))
    (themer-reader-form--rerender
     new (lambda () (themer-reader-form--goto-row (1- (length (plist-get new :palette))))))))

(defun themer-reader-form-palette-rename-entry (row)
  "Rename palette ROW, and every slot that names it."
  (let* ((state (themer-reader-form--state))
         (old (themer-reader-form--row-name row))
         (index (cl-position row themer-reader-form--palette-rows))
         (new (string-trim (read-string (format "Rename %s to: " old) old))))
    (unless (equal new old)
      (themer-reader-form--rerender (themer-reader-form-palette-rename state old new)
                                    (lambda () (themer-reader-form--goto-row index))))))

(defun themer-reader-form-palette-delete-entry (row)
  "Delete palette ROW.
If slots name it, ask first; they then take its hex."
  (let* ((state (themer-reader-form--state))
         (name (themer-reader-form--row-name row))
         (index (cl-position row themer-reader-form--palette-rows))
         (users (unless (cl-find name (remq (nth index (plist-get state :palette)) (plist-get state :palette))
                                 :key #'car :test #'equal)
                  (themer-reader-form-palette-users state name))))
    (when (and users
               (not (y-or-n-p (format "%s is used by %s; delete it and put its hex there? " name
                                      (mapconcat (lambda (k) (substring (symbol-name k) 1)) users ", ")))))
      (user-error "Not deleted"))
    (themer-reader-form--rerender
     (themer-reader-form-palette-delete state index t)
     (lambda () (themer-reader-form--goto-row (min index (1- (length themer-reader-form--palette-rows))))))))

(defun themer-reader-form--name-notify (widget &rest _)
  "Rename the palette entry of name field WIDGET as it is typed.
Once the text is a usable name no other entry has, the slots that named
the entry name it again."
  (let* ((old (widget-get widget :themer-name))
         (new (string-trim (widget-value widget)))
         (others (cl-loop for row in themer-reader-form--palette-rows
                          unless (eq (plist-get row :name) widget)
                          collect (themer-reader-form--row-name row))))
    (when (and (not (equal old new)) (themer-reader-form-name-ok new) (not (member new others)))
      (unless (member old others)
        (pcase-dolist (`(,key . ,w) themer-reader-form--widgets)
          (when (and (memq key (themer-reader-form--keys))
                     (themer-reader-form-name-ok old)
                     (equal (string-trim (widget-value w)) old))
            (save-excursion (widget-value-set w new)))))
      (widget-put widget :themer-name new)))
  (themer-reader-form--schedule))

(defconst themer-reader-form--base16-defaults
  '((:bg "base00") (:fg "base05") (:syntax "base0E") (:callable "base0D") (:type "base0A")
    (:value "base09") (:meta "base0C") (:error red) (:warning yellow) (:added green))
  "Default base16 slot per field; a hue name means the first accent slot with it.")

(defun themer-reader-form-base16-defaults (slots)
  "Alist KEY -> slot name: the default mapping of base16 SLOTS."
  (cl-loop for (key d) in themer-reader-form--base16-defaults
           collect (cons key (if (stringp d) d
                               (car (cl-find-if (lambda (s) (and (string-match-p "\\`base0[89A-F]" (car s))
                                                                 (eq (themer-colour-hue-name (cdr s)) d)))
                                                slots))))))

(defun themer-reader-form-import-base16 (&optional file)
  "Fill the palette from base16 (or base24) YAML FILE, and point the slots at it.
The palette gets an entry per slot, base00 to base0F (base17); each
field is asked which slot it names, defaulting to the base16 conventions."
  (interactive)
  (let* ((file (or file (read-file-name "base16 YAML: " nil nil t)))
         (slots (or (themer-reader--read-base16 file) (user-error "No base16 slots in %s" file)))
         (choices (mapcar (lambda (s) (cons (format "%s %s %s" (car s) (cdr s) (themer-reader-form--hue (cdr s)))
                                            (car s)))
                          slots))
         (picked
          (cl-loop for (key . slot) in (themer-reader-form-base16-defaults slots)
                   collect
                   (let* ((label (nth 1 (assq key themer-reader-form--fields)))
                          (def (car (cl-find-if (lambda (c) (and slot (equal slot (cdr c)))) choices)))
                          (c (completing-read (format "%s slot: " label) (cons "(none)" (mapcar #'car choices))
                                              nil t nil nil (or def "(none)"))))
                     (cons key (cdr (assoc c choices)))))))
    (themer-reader-form--rerender
     (themer-reader-form-base16-state (themer-reader-form--state) slots picked))))

(provide 'themer-reader-form)

;;; themer-reader-form.el ends here
