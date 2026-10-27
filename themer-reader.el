;;; themer-reader.el --- Themes that follow the reader colouring standard -*- lexical-binding: t; -*-

;; Author: beltsmith <me@alexgirdler.com>
;; Package-Requires: ((emacs "29.1"))

;;; Commentary:
;;
;; Generate Emacs themes from the reader standard (research/PATTERNS.md,
;; draft 3.2): "label quietly, landmark loudly".  A theme is a spec of a
;; background, a foreground and one accent per kind family:
;;
;;   (:bg "#282828" :fg "#d5c4a1"
;;    :syntax "#fb4934" :callable "#b8bb26" :type "#fabd2f"
;;    :value "#d3869b" :meta "#8ec07c"
;;    [:binding HEX] [:popout HEX] [:accent HEX]
;;    [:error HEX] [:warning HEX] [:added HEX] [:removed HEX])
;;
;; A spec may also define its colours once in a palette, an ordered list
;; of named entries, and name them in the slots:
;;
;;   (:palette ((bg "#282828") (fg "#d5c4a1") (red "#fb4934") ...)
;;    :bg bg :fg fg :syntax red ...)
;;
;; `themer-reader-resolve' replaces the names with their colours before
;; anything is derived.
;;
;; `themer-reader-derive' turns that into every salience tier (faded, dim,
;; recessive, default, quiet, loud, strong, popout) the way the reference
;; mapper does (research/harness/mapper.py, mode C), checks the standard's
;; MUSTs and SHOULDs, sheds families for reduced conformance, and maps the
;; roles onto Emacs faces.
;;
;;   `themer-reader-deftheme'     define a theme from a spec, in NAME-theme.el
;;   `themer-reader-new-theme'    create a theme in a form (themer-reader-form.el)
;;   `themer-reader-edit-theme'   edit a theme file in the same form
;;   `themer-reader-check'        show the conformance report
;;   `themer-reader-export'       write a standalone theme with baked colours
;;   `themer-reader-treesit-mode' extra tree-sitter rules for exits, type
;;                                definitions, decorators, module-level
;;                                bindings, constant definitions, TODO
;;                                markers and (optionally) commented-out code

;;; Code:

(require 'cl-lib)
(require 'subr-x)
(require 'treesit)
(require 'themer-colour)

(defvar themer-preview-mode)
(declare-function themer-preview-mode "themer-preview")
(declare-function treesit-primary-parser "treesit")

;;;; Options

(defcustom themer-reader-enable-rules t
  "Non-nil means loading a reader theme turns on `themer-reader-treesit-mode'."
  :type 'boolean
  :group 'themer)

(defcustom themer-reader-fade-commented-code nil
  "Non-nil means comments that look like code are drawn in the faded tier.
The detection is heuristic (see `themer-reader-commented-code-p')."
  :type 'boolean
  :group 'themer)

(defcustom themer-reader-italic-comments nil
  "Non-nil means comments are italic (the standard allows italic for prose)."
  :type 'boolean
  :group 'themer)

;;;; Where themes are found
;;
;; `load-theme' and `consult-theme' only see directories on
;; `custom-theme-load-path'.  Loading this library adds
;; `themer-reader-theme-directory' (and, with
;; `themer-reader-include-examples', the package's examples/) to it;
;; nothing is created on disk.

(defvar themer-reader--library-directory
  (when-let* ((file (or load-file-name buffer-file-name (locate-library "themer-reader"))))
    (file-name-directory file))
  "The directory this library was loaded from, or nil.")

(defun themer-reader--same-dir-p (a b)
  "Non-nil if directory names A and B are the same, existing or not."
  (equal (file-name-as-directory (expand-file-name a))
         (file-name-as-directory (expand-file-name b))))

(defun themer-reader-add-theme-directory (dir)
  "Put DIR on `custom-theme-load-path' if it isn't there already.
Return the directory name as stored, or nil if DIR is nil.  The
directory need not exist."
  (when dir
    (let ((dir (file-name-as-directory (expand-file-name dir))))
      (unless (cl-some (lambda (d) (and (stringp d)
                                        (themer-reader--same-dir-p d dir)))
                       custom-theme-load-path)
        (add-to-list 'custom-theme-load-path dir t))
      dir)))

(defun themer-reader--examples-directory ()
  "The package's examples/ directory, or nil if it isn't there."
  (when themer-reader--library-directory
    (let ((dir (expand-file-name "examples/" themer-reader--library-directory)))
      (and (file-directory-p dir) dir))))

(defun themer-reader--set-theme-directory (sym value)
  "Set SYM to VALUE, and put VALUE on `custom-theme-load-path'."
  (set-default sym value)
  (themer-reader-add-theme-directory value))

(defun themer-reader--set-include-examples (sym value)
  "Set SYM to VALUE; when non-nil, put the examples directory on the path."
  (set-default sym value)
  (if value
      (themer-reader-add-theme-directory (themer-reader--examples-directory))
    (when-let* ((dir (themer-reader--examples-directory)))
      (setq custom-theme-load-path
            (cl-remove-if (lambda (d) (and (stringp d) (themer-reader--same-dir-p d dir)))
                          custom-theme-load-path)))))

(defcustom themer-reader-theme-directory
  (locate-user-emacs-file "themes/")
  "Directory new reader themes are saved to, and searched for editing.
It is on `custom-theme-load-path', so the themes saved there appear in
`load-theme'."
  :type 'directory
  :set #'themer-reader--set-theme-directory
  :group 'themer)

(defcustom themer-reader-include-examples t
  "Non-nil means the example themes (examples/) are on `custom-theme-load-path'.
Then `load-theme' and `consult-theme' list reader-blush and the others."
  :type 'boolean
  :set #'themer-reader--set-include-examples
  :group 'themer)

;;;###autoload
(defun themer-reader-setup-theme-load-path ()
  "Put the reader theme directories on `custom-theme-load-path'.
That is `themer-reader-theme-directory' and, with
`themer-reader-include-examples', the package's examples/.  Call it
from your init file before `load-theme' when themer is loaded lazily;
the themes themselves load the rest.  Return the directories added."
  (delq nil (list (themer-reader-add-theme-directory themer-reader-theme-directory)
                  (and themer-reader-include-examples
                       (themer-reader-add-theme-directory (themer-reader--examples-directory))))))

;; `defcustom' runs :set only the first time a value is bound.
(themer-reader-setup-theme-load-path)

;;;; The standard (patterns/reader.yaml, draft 3.2)

(defconst themer-reader-families '(syntax callable type value meta)
  "The five kind families.")

(defconst themer-reader--drop-order '(meta type callable syntax value)
  "Families in ascending `keep' rank: the order reduced conformance sheds them.")

(defconst themer-reader--levels
  '((R0 . nil) (R1 . (meta)) (R2 . (meta type)))
  "Levels built in turn, with the families each sheds.")

(defconst themer-reader--styles
  '((keyword.decl syntax recessive) (keyword.flow syntax recessive)
    (keyword.other syntax recessive) (keyword.exit syntax strong)
    (variable.builtin syntax recessive) (operator nil default)
    (punctuation nil faded) (label syntax recessive)
    (function.def callable strong) (macro.def meta strong)
    (function.call callable quiet) (function.builtin callable quiet)
    (type.def type strong) (type.use type quiet) (type.builtin type quiet)
    (module type quiet)
    (string value quiet) (string.regexp value quiet) (string.escape value loud)
    (number value loud) (boolean value loud) (constant.builtin value loud)
    (constant.use value loud) (constant.def value strong)
    (attribute meta loud) (preproc meta loud) (macro.call meta quiet)
    (variable.def nil default) (variable.use nil default)
    (parameter binding quiet) (field nil default) (default nil default)
    (comment nil dim) (comment.doc nil dim) (comment.code nil dim)
    (comment.todo oddball popout)
    (mod.deprecated nil nil) (mod.unnecessary nil faded))
  "Role -> (FAMILY TIER), as in reader.yaml `styles'.")

(defconst themer-reader--fallbacks
  '((meta syntax loud) (type callable nil) (binding nil default))
  "Family -> (FALLBACK-FAMILY TIER-FOR-READING-LAYER-ROLES).")

(defconst themer-reader--loud-tiers '(loud strong popout))

(defconst themer-reader--tiers
  '(:faded (:lc (30 15) :chroma 0.03)
           :dim (:lc (45 20) :below 10 :chroma 0.04)
           :recessive (:below (6 18) :chroma (0.04 0.12))
           :default (:lc (60 45))
           :quiet (:within 12 :chroma (0.04 0.10))
           :loud (:lc (45 35) :chroma 0.08))
  "Tier parameters from reader.yaml `tiers'.")

(defconst themer-reader--max-fid 0.05
  "Fidelity cap: how far (ΔE_OK) an accent may move to reach its Lc target.")

;;;; Spec

(defconst themer-reader-slots
  '(:bg :fg :syntax :callable :type :value :meta :binding :popout :accent
    :error :warning :added :removed)
  "The colour slots of a spec, in canonical order.")

(defun themer-reader-palette-name-p (x)
  "Non-nil if X can name a palette entry: a symbol other than nil, t or a keyword."
  (and (symbolp x) x (not (eq x t)) (not (keywordp x))))

(defun themer-reader-palette (spec)
  "The palette of SPEC as an alist (NAME . HEX), in order.
Signal an error if the :palette list is malformed."
  (let (out)
    (dolist (e (plist-get spec :palette))
      (unless (and (consp e) (themer-reader-palette-name-p (car e))
                   (themer-colour-hex-p (cadr e)) (null (cddr e)))
        (error "Reader spec: palette entries are (NAME \"#rrggbb\"), got %S" e))
      (when (assq (car e) out)
        (error "Reader spec: palette entry %s is defined twice" (car e)))
      (push (cons (car e) (cadr e)) out))
    (nreverse out)))

(defun themer-reader-resolve (spec)
  "SPEC with each palette name replaced by its colour, and :palette dropped.
Slots holding a hex string are kept as they are.  Signal an error for a
name the palette doesn't define."
  (let ((pal (themer-reader-palette spec)) out)
    (cl-loop for (k v) on spec by #'cddr
             unless (eq k :palette)
             do (setq out (nconc out (list k (if (themer-reader-palette-name-p v)
                                                 (or (cdr (assq v pal))
                                                     (error (if (plist-get spec :palette)
                                                                "Reader spec: %s refers to %s, which is not in the palette"
                                                              "Reader spec: %s refers to %s, but the spec has no :palette")
                                                            k v))
                                               v)))))
    out))

(defun themer-reader-palette-users (spec name)
  "The slots of SPEC that refer to palette entry NAME, in spec order."
  (cl-loop for (k v) on spec by #'cddr
           when (and (memq k themer-reader-slots) (eq v name)) collect k))

(defun themer-reader--spec-get (spec key)
  "Normalised hex for KEY in resolved SPEC, or nil."
  (when-let* ((v (plist-get spec key)))
    (themer-colour-norm v)))

(defun themer-reader--fixed (spec key bg)
  "Hex for fixed-convention KEY of SPEC, with a default derived for BG."
  (or (themer-reader--spec-get spec key)
      (let ((l (if (themer-colour-dark-p bg) 0.68 0.52)))
        (pcase key
          (:error (themer-colour-from-oklch l 0.17 27))
          (:removed (themer-reader--fixed spec :error bg))
          (:warning (themer-colour-from-oklch (+ l 0.1) 0.15 80))
          (:added (themer-colour-from-oklch l 0.15 145))))))

(defun themer-reader--check-spec (spec)
  "Signal an error unless SPEC has the required keys.
Palette names are resolved first (`themer-reader-resolve')."
  (let ((spec (themer-reader-resolve spec)))
    (dolist (k '(:bg :fg :syntax :callable :value))
      (unless (themer-colour-hex-p (plist-get spec k))
        (error "Reader spec: %s must be a palette name or \"#rrggbb\" string, got %S"
               k (plist-get spec k))))
    (dolist (k '(:type :meta :binding :popout :accent :error :warning :added :removed))
      (when-let* ((v (plist-get spec k)))
        (unless (themer-colour-hex-p v)
          (error "Reader spec: %s must be a palette name or \"#rrggbb\" string, got %S" k v))))
    spec))

;;;; Styles after shedding

(defun themer-reader--effective-styles (kept)
  "Role -> plist (:family :tier :bold) after dropping families not in KEPT."
  (mapcar
   (pcase-lambda (`(,role ,fam ,tier))
     (let ((seen nil))
       (while (and fam (not (memq fam kept)) (not (eq fam 'oddball)))
         (if (memq fam seen)
             (setq fam nil)
           (push fam seen)
           (pcase-let ((`(,_ ,to ,ttier) (assq fam themer-reader--fallbacks)))
             (when (and ttier (memq tier '(quiet recessive)))
               (setq tier ttier))
             (setq fam to))))
       (when (and (null fam) (memq tier '(quiet recessive)))
         (setq tier 'default))
       (when (eq fam 'oddball) (setq fam nil))
       (cons role (list :family fam :tier tier
                        :bold (and (memq tier '(strong popout)) t)))))
   themer-reader--styles))

;;;; Tier derivation (mapper.py `dim_faded', `recessive_colour', `quiet_joint')

(defun themer-reader--arange (start stop step)
  "Like numpy.arange: START + i*STEP below STOP."
  (let ((n (max 0 (ceiling (/ (- stop start) step)))))
    (cl-loop for i below n collect (+ start (* i step)))))

(defun themer-reader--grid (lo hi)
  "Chroma grid LO..HI by 0.01, plus HI (numpy.unique of the two)."
  (sort (delete-dups (append (themer-reader--arange lo (+ hi 1e-9) 0.01) (list hi))) #'<))

(defun themer-reader--round (x digits)
  "X rounded to DIGITS decimals."
  (let ((m (expt 10.0 digits)))
    (/ (fround (* x m)) m)))

(defun themer-reader--lch (l c h)
  "Hex for OKLCH (L C H), rounded as mapper.py `_lch' does."
  (themer-colour-from-oklch (themer-reader--round l 4) (themer-reader--round c 4)
                            (themer-reader--round h 2)))

(defun themer-reader--dim-faded (fg bg)
  "Plist with :dim, :faded and their checks for FG on BG."
  (let* ((f (themer-colour-alc fg bg))
         (target (min 45 (- f 10)))
         (dim (themer-colour-cap-chroma (car (themer-colour-fade-to-lc fg bg target)) 0.04))
         (dlc (themer-colour-alc dim bg))
         (tt (min 30 (- dlc 1)))
         faded)
    (while (and (not faded) (>= tt 15))
      (let ((fd (themer-colour-cap-chroma (car (themer-colour-fade-to-lc fg bg tt)) 0.03)))
        (if (themer-colour-d1 fd dim)
            (setq faded fd)
          (setq tt (1- tt)))))
    (let ((faded-ok (and faded t)))
      (unless faded
        (setq faded (themer-colour-cap-chroma (car (themer-colour-fade-to-lc fg bg 15)) 0.03)))
      (list :dim dim :faded faded :dim-lc dlc
            :dim-floor-ok (>= dlc 19.5)
            :dim-below-ok (>= (- f dlc) 9.5)
            :faded-lc (themer-colour-alc faded bg)
            :faded-distinct-ok faded-ok))))

(defun themer-reader--recessive (acc fg bg avoid)
  "Recessive form of accent ACC for FG on BG, distinct from AVOID, or nil.
The point with the largest text difference from FG among those 6-18 Lc
below FG with chroma 0.04-0.12 and reliably distinct from FG and AVOID."
  (let* ((f (themer-colour-alc fg bg))
         (lf (car (themer-colour-oklch fg)))
         (ha (nth 2 (themer-colour-oklch acc)))
         best best-m)
    (dolist (c (themer-reader--grid 0.04 0.12))
      (dolist (l (themer-reader--arange (max 0.0 (- lf 0.35)) (+ (min 1.0 (+ lf 0.35)) 1e-9) 0.01))
        (let* ((q (themer-reader--lch l c ha))
               (d (- f (themer-colour-alc q bg)))
               (qc (nth 1 (themer-colour-oklch q))))
          (when (and (<= 6 d 18)
                     (<= (- 0.04 1e-3) qc (+ 0.12 1e-3))
                     (themer-colour-d1 q fg 'reliable)
                     (cl-every (lambda (a) (themer-colour-d1 q a 'reliable)) avoid))
            (let ((m (themer-colour-de-text q fg 0.8)))
              (when (or (null best) (> m best-m))
                (setq best q best-m m)))))))
    best))

(defun themer-reader--quiet-joint (accs fg bg avoid)
  "Quiet forms for ACCS, an alist (FAMILY . ACCENT) in shedding order.
Each is the accent's hue with chroma 0.04-0.10 and |Lc| within 12 of FG,
reliably distinct from FG, AVOID and each other, on BG.  Coordinate
search as in mapper.py `quiet_joint'.  Return (RESULT . FAILS): RESULT an
alist \(FAMILY . HEX-or-nil), FAILS an alist (FAMILY . REASON)."
  (let* ((f (themer-colour-alc fg bg))
         (lf (car (themer-colour-oklch fg)))
         (refs (cons fg avoid))
         (own-margin (lambda (q) (- (apply #'min (mapcar (lambda (a) (themer-colour-de-text q a 0.8)) refs)) 1)))
         cand fail live sel)
    (pcase-dolist (`(,fam . ,acc) accs)
      (let ((ha (nth 2 (themer-colour-oklch acc))) pool)
        (dolist (c (themer-reader--grid 0.04 0.10))
          (dolist (l (themer-reader--arange (max 0.0 (- lf 0.16)) (+ (min 1.0 (+ lf 0.16)) 1e-9) 0.01))
            (let ((q (themer-reader--lch l c ha)))
              (unless (member q pool)
                (let ((qc (nth 1 (themer-colour-oklch q))))
                  (when (and (<= (- 0.04 1e-3) qc (+ 0.10 1e-3))
                             (<= (abs (- (themer-colour-alc q bg) f)) 12)
                             (>= (funcall own-margin q) 0))
                    (push q pool)))))))
        (if pool
            (push (cons fam (vconcat (nreverse pool))) cand)
          (push (cons fam "no candidate distinct from fg/recessive/dim") fail))))
    (setq live (cl-remove-if-not (lambda (x) (assq x cand)) (mapcar #'car accs)))
    (catch 'found
      (while live
        (let* ((own (mapcar (lambda (x) (cons x (cl-map 'vector own-margin (alist-get x cand)))) live))
               (fgd (mapcar (lambda (x) (cons x (cl-map 'vector (lambda (q) (themer-colour-de-ok q fg))
                                                        (alist-get x cand))))
                            live))
               (pairs (cl-loop for (a . rest) on live append (mapcar (lambda (b) (cons a b)) rest)))
               (pm (mapcar (lambda (ab)
                             (let ((ca (alist-get (car ab) cand)) (cb (alist-get (cdr ab) cand)))
                               (cons ab (cl-map 'vector
                                                (lambda (qa)
                                                  (cl-map 'vector (lambda (qb) (- (themer-colour-de-text qa qb 0.8) 1)) cb))
                                                ca))))
                           pairs))
               (pmv (lambda (ab s) (aref (aref (cdr (assoc ab pm)) (alist-get (car ab) s)) (alist-get (cdr ab) s))))
               (score
                (lambda (s)
                  (let ((viol 0.0) (mm 1.0e+INF) (fsum 0.0))
                    (dolist (x live)
                      (setq mm (min mm (aref (alist-get x own) (alist-get x s)))
                            fsum (+ fsum (aref (alist-get x fgd) (alist-get x s)))))
                    (dolist (ab pairs)
                      (let ((v (funcall pmv ab s)))
                        (setq viol (+ viol (min 0.0 v)) mm (min mm v))))
                    (list (themer-reader--round viol 6) (min 0.20 mm) (- fsum)))))
               (better (lambda (a b)
                         (cond ((/= (nth 0 a) (nth 0 b)) (> (nth 0 a) (nth 0 b)))
                               ((/= (nth 1 a) (nth 1 b)) (> (nth 1 a) (nth 1 b)))
                               (t (> (nth 2 a) (nth 2 b))))))
               (argmax (lambda (v)
                         (let ((bi 0))
                           (dotimes (i (length v)) (when (> (aref v i) (aref v bi)) (setq bi i)))
                           bi)))
               best best-score)
          (dolist (start '(own chroma))
            (let* ((s (mapcar (lambda (x)
                                (cons x (funcall argmax
                                                 (if (eq start 'own)
                                                     (alist-get x own)
                                                   (cl-map 'vector (lambda (q) (- (nth 1 (themer-colour-oklch q))
                                                                                  (* 0.01 (themer-colour-de-ok q fg))))
                                                           (alist-get x cand))))))
                              live))
                   (cur (funcall score s))
                   (moved t)
                   (pass 0))
              (while (and moved (< pass 12))
                (setq moved nil pass (1+ pass))
                (dolist (x live)
                  (dotimes (i (length (alist-get x cand)))
                    (unless (= i (alist-get x s))
                      (let* ((tr (cons (cons x i) (assq-delete-all x (copy-alist s))))
                             (sc (funcall score tr)))
                        (when (funcall better sc cur)
                          (setq cur sc s tr moved t)))))))
              (when (or (null best) (funcall better cur best-score))
                (setq best s best-score cur))))
          (setq sel best)
          (when (>= (nth 0 best-score) 0)
            (throw 'found nil))
          (let ((cnt (mapcar (lambda (x) (cons x 0.0)) live))
                (worst (car live)))
            (dolist (ab pairs)
              (let ((m (funcall pmv ab sel)))
                (when (< m 0)
                  (cl-incf (alist-get (car ab) cnt) (- 1 (* m 1e-3)))
                  (cl-incf (alist-get (cdr ab) cnt) (- 1 (* m 1e-3))))))
            ;; Most violations; ties go to the family shed first.
            (dolist (x live)
              (when (> (alist-get x cnt) (alist-get worst cnt)) (setq worst x)))
            (push (cons worst "not distinct from another quiet colour") fail)
            (setq live (remq worst live))))))
    (cons (mapcar (lambda (x)
                    (cons (car x) (and (memq (car x) live)
                                       (aref (alist-get (car x) cand) (alist-get (car x) sel)))))
                  accs)
          fail)))

;;;; Building one level

(defun themer-reader--loud (spec bg)
  "Alist (FAMILY . plist) of SPEC's family accents, shifted toward Lc 45 on BG."
  (cl-loop for fam in (append themer-reader-families '(binding))
           for src = (themer-reader--spec-get spec (intern (format ":%s" fam)))
           when src
           collect (pcase-let ((`(,hex ,lc ,fid) (themer-colour-shift-l-to-lc
                                                  src bg 45 themer-reader--max-fid)))
                     (cons fam (list :src src :hex hex :lc lc :fid fid
                                     :name (themer-colour-hue-name hex))))))

(defun themer-reader--popout (spec loud fg bg)
  "Popout ink for SPEC: :popout, or the first fixed colour whose hue is unused.
LOUD is the family accent alist; FG and BG the default ink and background.
Return (HEX . SPARE-P)."
  (let* ((used (cons (themer-colour-hue-name fg)
                     (mapcar (lambda (x) (plist-get (cdr x) :name)) loud)))
         (cands (delq nil (list (themer-reader--spec-get spec :popout)
                                (themer-reader--fixed spec :warning bg)
                                (themer-reader--fixed spec :error bg)
                                (themer-reader--fixed spec :added bg))))
         (shift (lambda (h) (car (themer-colour-shift-l-to-lc h bg 45 themer-reader--max-fid))))
         (pick (cl-find-if (lambda (h) (not (memq (themer-colour-hue-name (funcall shift h)) used)))
                           cands)))
    (if pick
        (cons (funcall shift pick) t)
      (cons (funcall shift (car cands)) nil))))

(defun themer-reader--accent (spec loud)
  "The UI accent of SPEC: :accent, else :popout, else the callable loud colour.
LOUD is the family accent alist (as `themer-reader--loud').  It is never
applied to syntax faces."
  (or (themer-reader--spec-get spec :accent)
      (themer-reader--spec-get spec :popout)
      (plist-get (alist-get 'callable loud) :hex)))

(defun themer-reader--build (spec name kept loud fg bg)
  "Build level NAME of SPEC with families KEPT.  LOUD as `themer-reader--loud'."
  (let* ((styles (themer-reader--effective-styles
                  (if (assq 'binding loud) (cons 'binding kept) kept)))
         (fam-out (cl-remove-if-not (lambda (x) (memq (car x) kept)) loud))
         (fams (cl-remove-if-not (lambda (f) (assq f fam-out)) themer-reader--drop-order))
         (df (themer-reader--dim-faded fg bg))
         (dim (plist-get df :dim)) (faded (plist-get df :faded))
         (syn (plist-get (alist-get 'syntax fam-out) :hex))
         (rec (themer-reader--recessive syn fg bg (list dim faded syn)))
         (qfams (cl-remove-if-not
                 (lambda (f) (cl-some (lambda (r) (and (eq (plist-get (cdr r) :family) f)
                                                       (eq (plist-get (cdr r) :tier) 'quiet)))
                                      styles))
                 fams))
         (qaccs (mapcar (lambda (f) (cons f (plist-get (alist-get f fam-out) :hex))) qfams))
         (qj (themer-reader--quiet-joint qaccs fg bg (append (and rec (list rec)) (list dim))))
         (quiet (car qj))
         ;; The optional parameter tint is found after the other cues, as in
         ;; mapper.py `apply_options': it must not move them.
         (binding (alist-get 'binding loud))
         (bq (when binding
               (themer-reader--quiet-joint
                (list (cons 'binding (plist-get binding :src))) fg bg
                (append (and rec (list rec)) (list dim) (delq nil (mapcar #'cdr quiet))))))
         (bhex (cdr (assq 'binding (car bq))))
         (popout (themer-reader--popout spec fam-out fg bg))
         (roles
          (mapcar
           (lambda (r)
             (let* ((st (cdr r)) (fam (plist-get st :family)) (tier (plist-get st :tier))
                    (hex fg))
               (cond
                ((null tier) (setq hex nil))
                ((and (eq fam 'binding) (eq tier 'quiet))
                 (if bhex (setq hex bhex)
                   (setq fam nil tier 'default)))
                ((and fam (eq tier 'recessive))
                 (if rec (setq hex rec) (setq fam nil tier 'default)))
                ((and fam (eq tier 'quiet))
                 (if-let* ((q (alist-get fam quiet))) (setq hex q)
                   (setq fam nil tier 'default)))
                (fam (setq hex (plist-get (alist-get fam fam-out) :hex)))
                ((eq tier 'popout) (setq hex (car popout)))
                ((eq tier 'faded) (setq hex faded))
                ((eq tier 'dim) (setq hex dim)))
               (cons (car r) (list :foreground hex :family fam :tier tier
                                   :bold (plist-get st :bold)
                                   :strike (eq (car r) 'mod.deprecated)))))
           styles)))
    (list :name name :kept kept :styles styles :families fam-out :fams fams
          :dim dim :faded faded :tiers-info df :recessive rec
          :quiet quiet
          :binding (and binding (list :hex bhex :src (plist-get binding :src)
                                      :reason (alist-get 'binding (cdr bq))))
          :quiet-fails (cdr qj) :qfams qfams
          :popout popout :roles roles)))

(defun themer-reader--loud-checks (b bg)
  "Loud-family checks for build B on BG: pairs, L2 per family, overall flags."
  (let* ((fam-out (plist-get b :families))
         (styles (plist-get b :styles))
         (fams (plist-get b :fams))
         (loud-fams (cl-remove-if-not
                     (lambda (f) (cl-some (lambda (r) (and (eq (plist-get (cdr r) :family) f)
                                                           (memq (plist-get (cdr r) :tier) themer-reader--loud-tiers)))
                                          styles))
                     fams))
         (hex (lambda (f) (plist-get (alist-get f fam-out) :hex)))
         (pairs (cl-loop for (a . rest) on loud-fams
                         append (mapcar
                                 (lambda (bb)
                                   (let* ((ha (funcall hex a)) (hb (funcall hex bb))
                                          (n (themer-colour-d2 ha hb nil t))
                                          (d (themer-colour-d1 (themer-colour-cvd ha 'deutan) (themer-colour-cvd hb 'deutan) 'reliable))
                                          (p (themer-colour-d1 (themer-colour-cvd ha 'protan) (themer-colour-cvd hb 'protan) 'reliable)))
                                     (list (cons a bb) :normal n :deutan d :protan p)))
                                 rest)))
         (l2 (mapcar (lambda (f)
                       (let ((tiers (delq nil (mapcar (lambda (r)
                                                        (let ((st (cdr r)))
                                                          (when (and (eq (plist-get st :family) f)
                                                                     (memq (plist-get st :tier) themer-reader--loud-tiers))
                                                            (themer-colour-lc-tier (themer-colour-alc (funcall hex f) bg)
                                                                                   'L2 (plist-get st :bold)))))
                                                      styles))))
                         (cons f (if tiers
                                     (car (sort tiers (lambda (x y) (> (cl-position x '(strict default floor fail))
                                                                       (cl-position y '(strict default floor fail))))))
                                   'n/a))))
                     fams))
         (ti (plist-get b :tiers-info))
         (dim-ok (and (plist-get ti :dim-floor-ok) (plist-get ti :dim-below-ok)))
         (base (and (cl-every (lambda (x) (not (eq (cdr x) 'fail))) l2) dim-ok))
         (failures
          (append
           (delq nil (mapcar (lambda (e)
                               (let ((bad (delq nil (list (unless (plist-get (cdr e) :normal) "D2")
                                                          (unless (plist-get (cdr e) :deutan) "deutan")
                                                          (unless (plist-get (cdr e) :protan) "protan")))))
                                 (when bad (format "%s/%s: %s" (caar e) (cdar e) (string-join bad ", ")))))
                             pairs))
           (delq nil (mapcar (lambda (x) (when (eq (cdr x) 'fail) (format "L2 %s (fail)" (car x)))) l2))
           (unless dim-ok (list "dim"))
           (unless (plist-get b :recessive) (list "recessive"))
           (delq nil (mapcar (lambda (f) (unless (alist-get f (plist-get b :quiet)) (format "quiet %s" f)))
                             (plist-get b :qfams))))))
    (list :pairs pairs :l2 l2 :dim-ok dim-ok
          :loud-ok (and base (cl-every (lambda (e) (and (plist-get (cdr e) :normal) (plist-get (cdr e) :deutan)
                                                        (plist-get (cdr e) :protan)))
                                       pairs))
          :loud-ok-normal (and base (cl-every (lambda (e) (plist-get (cdr e) :normal)) pairs))
          :recessive-ok (and (plist-get b :recessive) t)
          :quiet-ok (cl-every (lambda (f) (alist-get f (plist-get b :quiet))) (plist-get b :qfams))
          :failures failures)))

(defun themer-reader--pick-level (built key)
  "(BUILD . LEVEL) for BUILT, using loud flag KEY (:loud-ok or :loud-ok-normal)."
  (or (cl-loop for b in built
               for c = (plist-get b :checks)
               when (and (plist-get c key) (plist-get c :recessive-ok) (plist-get c :quiet-ok))
               return (cons b (plist-get b :name)))
      (let* ((last (car (last built))) (c (plist-get last :checks)))
        (cond ((not (eq (plist-get last :name) 'R2)) (cons (car built) 'none))
              ((and (plist-get c key) (plist-get c :recessive-ok)) (cons last 'R3))
              ((plist-get c key) (cons last 'R4))
              (t (cons (car built) 'none))))))

;;;; Conformance report

(defun themer-reader--check (id section kw ok detail &optional gating)
  "One conformance entry ID of SECTION, keyword KW, result OK and DETAIL.
GATING nil means it doesn't affect the level."
  (list :id id :section section :keyword kw :ok (and ok t) :detail detail
        :gating gating))

(defun themer-reader--conformance (spec b bg fg level level-cvd)
  "Every MUST/SHOULD of PATTERNS.md §1-§4 for build B of SPEC."
  (let* ((c (plist-get b :checks))
         (ti (plist-get b :tiers-info))
         (f (themer-colour-alc fg bg))
         (dim (plist-get b :dim)) (faded (plist-get b :faded))
         (rec (plist-get b :recessive))
         (fam-out (plist-get b :families))
         (chroma (lambda (h) (nth 1 (themer-colour-oklch h))))
         (lc (lambda (h) (themer-colour-alc h bg)))
         (fmt (lambda (h) (format "%s Lc %.1f C %.3f" h (funcall lc h) (funcall chroma h))))
         (fixed (lambda (k) (themer-reader--fixed spec k bg)))
         (popout (plist-get b :popout))
         (accent (themer-reader--accent spec fam-out))
         (checks
          (append
           (list
            (themer-reader--check 'error-red "§1" 'MUST (eq (themer-colour-hue-name (funcall fixed :error)) 'red)
                                  (format "error %s is %s" (funcall fixed :error) (themer-colour-hue-name (funcall fixed :error))))
            (themer-reader--check 'warning-yellow "§1" 'SHOULD (memq (themer-colour-hue-name (funcall fixed :warning)) '(yellow orange brown))
                                  (format "warning %s is %s" (funcall fixed :warning) (themer-colour-hue-name (funcall fixed :warning))))
            (themer-reader--check 'added-green "§1" 'MUST (eq (themer-colour-hue-name (funcall fixed :added)) 'green)
                                  (format "added %s is %s" (funcall fixed :added) (themer-colour-hue-name (funcall fixed :added))))
            (themer-reader--check 'removed-red "§1" 'MUST (eq (themer-colour-hue-name (funcall fixed :removed)) 'red)
                                  (format "removed %s is %s" (funcall fixed :removed) (themer-colour-hue-name (funcall fixed :removed))))
            (themer-reader--check 'faded-lc "§2" 'MUST (>= (funcall lc faded) 15)
                                  (format "faded %s; Lc ≥ 15" (funcall fmt faded)) t)
            (themer-reader--check 'faded-target "§2" 'SHOULD
                                  (and (<= (abs (- (funcall lc faded) 30)) 5) (<= (funcall chroma faded) 0.03)
                                       (plist-get ti :faded-distinct-ok))
                                  "faded Lc ≈ 30, achromatic, distinct from dim")
            (themer-reader--check 'dim "§2" 'MUST (plist-get c :dim-ok)
                                  (format "dim %s; Lc ≥ 20, ≥ 10 below default (%.1f), C ≤ 0.04" (funcall fmt dim) f) t)
            (themer-reader--check 'dim-target "§2" 'SHOULD (<= (abs (- (funcall lc dim) 45)) 5)
                                  (format "Lc %.1f ≈ 45" (funcall lc dim)))
            (themer-reader--check 'recessive "§2" 'MUST rec
                                  (if rec (format "recessive %s; %.1f below default" (funcall fmt rec) (- f (funcall lc rec)))
                                    "no colour 6-18 Lc below default, C 0.04-0.12, reliably distinct from default, dim, faded and the syntax accent")
                                  t)
            (themer-reader--check 'default-lc "§2" 'MUST (>= f 45) (format "fg %s Lc %.1f ≥ 45" fg f) t)
            (themer-reader--check 'default-target "§2" 'SHOULD (>= f 60) (format "fg Lc %.1f ≥ 60" f)))
           (mapcar (lambda (fam)
                     (let ((q (alist-get fam (plist-get b :quiet))))
                       (themer-reader--check (intern (format "quiet-%s" fam)) "§2" 'MUST q
                                             (if q (format "%s quiet %s" fam (funcall fmt q))
                                               (format "%s: %s" fam (alist-get fam (plist-get b :quiet-fails))))
                                             t)))
                   (plist-get b :qfams))
           (mapcar (lambda (x)
                     (let ((h (plist-get (cdr x) :hex)))
                       (themer-reader--check (intern (format "loud-%s" (car x))) "§2" 'MUST
                                             (not (eq (alist-get (car x) (plist-get c :l2)) 'fail))
                                             (format "%s %s; L2 %s (35, or 25 when only bold)" (car x) (funcall fmt h)
                                                     (alist-get (car x) (plist-get c :l2)))
                                             t)))
                   fam-out)
           (mapcar (lambda (x)
                     (let ((h (plist-get (cdr x) :hex)))
                       (themer-reader--check (intern (format "loud-chroma-%s" (car x))) "§2" 'MUST
                                             (>= (funcall chroma h) 0.08)
                                             (format "%s C %.3f ≥ 0.08 (reported, not gating, as harness mode C)"
                                                     (car x) (funcall chroma h)))))
                   fam-out)
           (mapcar (lambda (x)
                     (let ((h (plist-get (cdr x) :hex)))
                       (themer-reader--check (intern (format "loud-target-%s" (car x))) "§2" 'SHOULD
                                             (>= (funcall lc h) 45)
                                             (format "%s Lc %.1f ≥ 45 (moved ΔE_OK %.3f from %s)"
                                                     (car x) (funcall lc h) (plist-get (cdr x) :fid) (plist-get (cdr x) :src)))))
                   fam-out)
           (list
            (themer-reader--check 'popout "§2" 'SHOULD (cdr popout)
                                  (format "TODO ink %s (%s) %s" (car popout) (themer-colour-hue-name (car popout))
                                          (if (cdr popout) "uses a hue no family uses" "shares a family hue"))))
           (list
            (themer-reader--check 'accent-lc "§1" 'SHOULD (>= (funcall lc accent) 60)
                                  (format "UI accent %s Lc %.1f ≥ 60 on the background%s"
                                          accent (funcall lc accent)
                                          (if (plist-get spec :accent) ""
                                            (if (plist-get spec :popout) " (default: popout)"
                                              " (default: callable)"))))
            (themer-reader--check 'accent-isearch "§1" 'SHOULD
                                  (>= (abs (themer-colour-alc bg accent)) 60)
                                  (format "isearch text on the accent: Lc %.1f ≥ 60"
                                          (abs (themer-colour-alc bg accent)))))
           (mapcar (lambda (e)
                     (themer-reader--check (intern (format "distinct-%s-%s" (caar e) (cdar e))) "§3" 'MUST
                                           (plist-get (cdr e) :normal)
                                           (format "%s/%s categorically distinct (D1 floor, different hue name)" (caar e) (cdar e))
                                           t))
                   (plist-get c :pairs))
           (mapcar (lambda (e)
                     (themer-reader--check (intern (format "cvd-%s-%s" (caar e) (cdar e))) "§3" 'SHOULD
                                           (and (plist-get (cdr e) :deutan) (plist-get (cdr e) :protan))
                                           (format "%s/%s reliably distinct: deutan %s, protan %s" (caar e) (cdar e)
                                                   (if (plist-get (cdr e) :deutan) "ok" "fail")
                                                   (if (plist-get (cdr e) :protan) "ok" "fail"))))
                   (plist-get c :pairs))
           (when-let* ((bd (plist-get b :binding)))
             (let ((h (plist-get bd :hex)))
               (list (themer-reader--check 'binding "§3" 'MUST h
                                           (if h (format "parameter tint %s" (funcall fmt h))
                                             (format "parameter tint dropped: %s" (plist-get bd :reason))))
                     (let ((gap (themer-reader--binding-gap h (plist-get b :quiet))))
                       (themer-reader--check 'binding-hue "§3" 'SHOULD (and gap (>= gap 40))
                                             (if gap (format "parameter tint hue is %.0f° from the nearest quiet cue (≥ 40)" gap)
                                               "no parameter tint"))))))
           (list
            (themer-reader--check 'level "§4" 'MUST t
                                  (format "level %s (normal vision %s; with the CVD checks %s)"
                                          (themer-reader--level-string level level-cvd) level level-cvd))))))
    checks))

(defun themer-reader--binding-gap (hex quiet)
  "Smallest OKLCH hue distance from HEX to the colours in alist QUIET."
  (when hex
    (let ((h (nth 2 (themer-colour-oklch hex))))
      (cl-loop for (_ . q) in quiet
               when q
               minimize (let ((d (mod (abs (- h (nth 2 (themer-colour-oklch q)))) 360)))
                          (min d (- 360 d)))
               into m
               finally return (or m 180.0)))))

(defun themer-reader--level-string (level level-cvd)
  "Display name for LEVEL (normal vision) given LEVEL-CVD."
  (cond ((and (eq level 'R0) (eq level-cvd 'R0)) "full+cvd")
        ((eq level 'R0) "full")
        (t (symbol-name level))))

;;;; Derivation

(defvar themer-reader--cache (make-hash-table :test #'equal)
  "Resolved spec -> derivation, so re-evaluating an unchanged theme is instant.")

(defun themer-reader--ui (spec bg fg)
  "Background and state tiers for the UI, by OKLab mixing of BG and FG.
The fixed-convention colours come from SPEC."
  (let ((m (lambda (a b tt) (themer-colour-mix a b tt))))
    (list :subtle (funcall m bg fg 0.06)
          :raised (funcall m bg fg 0.12)
          :strong (funcall m bg fg 0.22)
          :border (funcall m bg fg 0.30)
          :error (themer-reader--fixed spec :error bg)
          :warning (themer-reader--fixed spec :warning bg)
          :added (themer-reader--fixed spec :added bg)
          :removed (themer-reader--fixed spec :removed bg))))

(defun themer-reader-derive (spec)
  "Derive every tier, role and conformance check of reader SPEC.
Return a plist:
  :roles        alist ROLE -> (:foreground :weight :slant :strike)
  :tiers        plist of derived colours (:dim :faded :recessive :quiet
                :loud :popout :binding and the UI tiers)
  :conformance  plist (:level STRING :level-normal SYM :level-cvd SYM
                :checks LIST :failures LIST :levels ALIST)
  :spec         SPEC resolved: palette names replaced by their colours
The level is reached under normal vision; \"full+cvd\" also meets the CVD
SHOULDs.  Faces follow the normal-vision level.  Results are cached on
the resolved colours."
  (setq spec (themer-reader--check-spec spec))
  (with-memoization (gethash (list spec themer-reader-italic-comments themer-reader-fade-commented-code)
                             themer-reader--cache)
    (let* ((bg (themer-colour-norm (plist-get spec :bg)))
           (fg (themer-colour-norm (plist-get spec :fg)))
           (loud (themer-reader--loud spec bg))
           (avail (cl-remove-if-not (lambda (f) (assq f loud)) themer-reader-families))
           (built (mapcar (pcase-lambda (`(,name . ,shed))
                            (let ((b (themer-reader--build spec name (cl-set-difference avail shed) loud fg bg)))
                              (plist-put b :checks (themer-reader--loud-checks b bg))))
                          themer-reader--levels))
           (pick (themer-reader--pick-level built :loud-ok-normal))
           (level-cvd (cdr (themer-reader--pick-level built :loud-ok)))
           (b (car pick)) (level (cdr pick))
           (roles (mapcar
                   (lambda (r)
                     (let* ((p (cdr r)) (role (car r))
                            (hex (plist-get p :foreground)))
                       ;; R3/R4 shed failing reading-layer cues to default ink
                       ;; (already done when the colour failed).
                       (when (and (eq role 'comment.code) themer-reader-fade-commented-code)
                         (setq hex (plist-get b :faded)))
                       (cons role (list :foreground hex
                                        :weight (if (plist-get p :bold) 'bold 'normal)
                                        :slant (if (and themer-reader-italic-comments
                                                        (memq role '(comment comment.doc comment.code)))
                                                   'italic 'normal)
                                        :strike (plist-get p :strike)
                                        :family (plist-get p :family)
                                        :tier (plist-get p :tier)))))
                   (plist-get b :roles)))
           (checks (themer-reader--conformance spec b bg fg level level-cvd)))
      (list :spec spec
            :roles roles
            :tiers (append (list :bg bg :fg fg
                                 :dim (plist-get b :dim) :faded (plist-get b :faded)
                                 :recessive (plist-get b :recessive)
                                 :quiet (plist-get b :quiet)
                                 :loud (mapcar (lambda (x) (cons (car x) (plist-get (cdr x) :hex)))
                                               (plist-get b :families))
                                 :binding (plist-get (plist-get b :binding) :hex)
                                 :popout (car (plist-get b :popout))
                                 :accent (themer-reader--accent spec loud))
                           (themer-reader--ui spec bg fg))
            :conformance
            (list :level (themer-reader--level-string level level-cvd)
                  :level-normal level :level-cvd level-cvd
                  :build (plist-get b :name)
                  :checks checks
                  :failures (plist-get (plist-get b :checks) :failures)
                  :levels (mapcar (lambda (x) (cons (plist-get x :name)
                                                    (list :loud-ok (plist-get (plist-get x :checks) :loud-ok)
                                                          :loud-ok-normal (plist-get (plist-get x :checks) :loud-ok-normal)
                                                          :recessive-ok (plist-get (plist-get x :checks) :recessive-ok)
                                                          :quiet-ok (plist-get (plist-get x :checks) :quiet-ok)
                                                          :failures (plist-get (plist-get x :checks) :failures))))
                                  built))))))

;;;; Terminal colours

(defconst themer-reader--ansi-hues
  '((red . 27) (green . 145) (yellow . 95) (blue . 255) (magenta . 330) (cyan . 200))
  "ANSI colour -> OKLCH hue, for a colour the theme has no match for.")

(defun themer-reader--ansi (tiers)
  "Alist ANSI-NAME -> (NORMAL . BRIGHT) hex colours for TIERS.
The colours must look like their names whatever the families' hues.
Each is the first of the error, added or warning colour (for red, green
and yellow: the meanings terminals give them) and the loud family
colours that has its hue name and Lc >= 35 (the loud MUST), else one
made at the loud colours' mean lightness and chroma.  Bright forms are
0.08 lighter (darker on a light background).  Black and white are
neutral: on a dark background black is the raised surface and bright
black dim ink (grey text must stay readable), white is between dim and
default ink and bright white the default; a light background swaps the
roles."
  (let* ((tg (lambda (k) (plist-get tiers k)))
         (dark (themer-colour-dark-p (funcall tg :bg)))
         (louds (mapcar #'cdr (funcall tg :loud)))
         (lc (mapcar #'themer-colour-oklch louds))
         (l (/ (apply #'+ (mapcar #'car lc)) (float (length lc))))
         (c (max 0.08 (/ (apply #'+ (mapcar #'cadr lc)) (float (length lc)))))
         (bright (lambda (hex)
                   (pcase-let ((`(,hl ,hc ,hh) (themer-colour-oklch hex)))
                     (themer-colour-from-oklch (+ hl (if dark 0.08 -0.08)) hc hh)))))
    (append
     (cl-loop for (name . hue) in themer-reader--ansi-hues
              for names = (pcase name ('magenta '(purple pink)) (_ (list name)))
              for hex = (or (cl-find-if
                             (lambda (x)
                               (and x (memq (themer-colour-hue-name x) names)
                                    (>= (themer-colour-alc x (funcall tg :bg)) 35)))
                             (cons (pcase name
                                     ('red (funcall tg :error))
                                     ('green (funcall tg :added))
                                     ('yellow (funcall tg :warning)))
                                   louds))
                            (themer-colour-from-oklch l c hue))
              collect (cons name (cons hex (funcall bright hex))))
     (if dark
         `((black ,(funcall tg :raised) . ,(funcall tg :dim))
           (white ,(themer-colour-mix (funcall tg :dim) (funcall tg :fg) 0.5) . ,(funcall tg :fg)))
       `((black ,(funcall tg :fg) . ,(funcall tg :dim))
         (white ,(funcall tg :raised) . ,(funcall tg :subtle)))))))

;;;; Faces

(defface themer-reader-exit
  '((t :inherit font-lock-keyword-face :weight bold))
  "Exits: return, raise/throw, break, continue, yield, goto, Rust `?'."
  :group 'themer)

(defface themer-reader-type-definition
  '((t :inherit font-lock-type-face :weight bold))
  "The name in a type definition."
  :group 'themer)

(defface themer-reader-module
  '((t :inherit font-lock-type-face))
  "Module and namespace names in paths."
  :group 'themer)

(defface themer-reader-meta
  '((t :inherit font-lock-preprocessor-face))
  "Decorators, attributes and annotations."
  :group 'themer)

(defface themer-reader-macro-call
  '((t :inherit font-lock-preprocessor-face))
  "Macro invocations."
  :group 'themer)

(defface themer-reader-macro-definition
  '((t :inherit font-lock-preprocessor-face :weight bold))
  "The name in a macro definition."
  :group 'themer)

(defface themer-reader-todo
  '((t :inherit font-lock-warning-face :weight bold))
  "TODO, FIXME and XXX markers in comments."
  :group 'themer)

(defface themer-reader-commented-code
  '((t :inherit shadow))
  "Comments that look like code (see `themer-reader-fade-commented-code')."
  :group 'themer)

(defface themer-reader-parameter
  '((t :inherit font-lock-variable-name-face))
  "Parameter declarations."
  :group 'themer)

(defface themer-reader-module-variable
  '((t :inherit font-lock-variable-name-face :weight bold))
  "Module-level variable bindings (locals keep the plain variable face)."
  :group 'themer)

(defface themer-reader-constant-definition
  '((t :inherit font-lock-constant-face :weight bold))
  "The name in a constant definition."
  :group 'themer)

(defun themer-reader--attrs (derived role)
  "Face attributes for ROLE in DERIVED."
  (let ((r (alist-get role (plist-get derived :roles))))
    (append (when (plist-get r :foreground) (list :foreground (plist-get r :foreground)))
            (list :weight (plist-get r :weight) :slant (plist-get r :slant))
            (when (plist-get r :strike) (list :strike-through t)))))

(defun themer-reader-faces (derived)
  "Alist (FACE . ATTRIBUTES) for a theme from DERIVED (`themer-reader-derive')."
  (let* ((tiers (plist-get derived :tiers))
         (tg (lambda (k) (plist-get tiers k)))
         (bg (funcall tg :bg)) (fg (funcall tg :fg))
         (dim (funcall tg :dim)) (faded (funcall tg :faded))
         (subtle (funcall tg :subtle)) (raised (funcall tg :raised))
         (strong (funcall tg :strong)) (border (funcall tg :border))
         (accent (funcall tg :accent))
         (err (funcall tg :error)) (warn (funcall tg :warning))
         (add (funcall tg :added)) (rem (funcall tg :removed))
         (loud (lambda (f) (or (alist-get f (funcall tg :loud))
                               (alist-get 'callable (funcall tg :loud)))))
         (mix (lambda (a tt) (themer-colour-mix bg a tt)))
         (r (lambda (role) (themer-reader--attrs derived role)))
         (wave (lambda (c) (list :underline (list :style 'wave :color c))))
         (plain '(:weight normal :slant normal))
         (prose (and themer-reader-italic-comments '(:slant italic))))
    `(;; Basics
      (default :foreground ,fg :background ,bg)
      (cursor :background ,accent)
      (region :background ,raised :extend t)
      (secondary-selection :background ,strong :extend t)
      (hl-line :background ,subtle :extend t)
      (highlight :background ,strong)
      (shadow :foreground ,dim)
      (fringe :foreground ,faded :background ,bg)
      (vertical-border :foreground ,border)
      (window-divider :foreground ,border)
      (window-divider-first-pixel :foreground ,border)
      (window-divider-last-pixel :foreground ,border)
      (line-number :foreground ,faded :background ,bg)
      (line-number-current-line :foreground ,accent :background ,subtle :weight bold)
      (mode-line :foreground ,fg :background ,raised :box (:line-width 1 :color ,border))
      (mode-line-active :inherit mode-line)
      (mode-line-inactive :foreground ,dim :background ,subtle :box (:line-width 1 :color ,raised))
      (mode-line-highlight :box (:line-width 1 :color ,accent))
      (mode-line-buffer-id :foreground ,accent :weight bold)
      (header-line :foreground ,fg :background ,subtle)
      (header-line-highlight :inherit mode-line-highlight)
      (tab-bar :foreground ,dim :background ,subtle)
      (tab-bar-tab :foreground ,fg :background ,raised :weight bold)
      (tab-bar-tab-inactive :foreground ,dim :background ,subtle)
      (minibuffer-prompt :foreground ,accent :weight bold)
      (tooltip :foreground ,fg :background ,raised)
      (link :foreground ,(funcall loud 'callable) :underline t)
      (link-visited :foreground ,(funcall loud 'value) :underline t)
      (button :inherit link)
      (help-key-binding :foreground ,accent :background ,subtle
                        :box (:line-width -1 :color ,border))
      (error :foreground ,err :weight bold)
      (warning :foreground ,warn :weight bold)
      (success :foreground ,add :weight bold)
      (escape-glyph :foreground ,(funcall loud 'value))
      (homoglyph :foreground ,(funcall loud 'value))
      (nobreak-space :foreground ,(funcall loud 'value) :underline t)
      (trailing-whitespace :background ,(funcall mix err 0.45))
      ;; Search and parens
      (isearch :foreground ,bg :background ,accent :weight bold)
      (isearch-fail :background ,(funcall mix err 0.35))
      (lazy-highlight :foreground ,fg :background ,(funcall mix warn 0.30))
      (match :foreground ,fg :background ,(funcall mix warn 0.30))
      (query-replace :inherit isearch)
      (show-paren-match :foreground ,accent :background ,raised :weight bold)
      (show-paren-mismatch :foreground ,bg :background ,err)
      ;; Code (font-lock and tree-sitter)
      (font-lock-keyword-face ,@(funcall r 'keyword.other))
      (font-lock-function-name-face ,@(funcall r 'function.def))
      (font-lock-function-call-face ,@(funcall r 'function.call))
      (font-lock-variable-name-face ,@(funcall r 'variable.use))
      (font-lock-variable-use-face ,@(funcall r 'variable.use))
      (font-lock-property-name-face ,@(funcall r 'field))
      (font-lock-property-use-face ,@(funcall r 'field))
      (font-lock-type-face ,@(funcall r 'type.use))
      (font-lock-constant-face ,@(funcall r 'constant.use))
      (font-lock-builtin-face ,@(funcall r 'function.builtin))
      (font-lock-string-face ,@(funcall r 'string))
      (font-lock-escape-face ,@(funcall r 'string.escape))
      (font-lock-regexp-face ,@(funcall r 'string.regexp))
      (font-lock-regexp-grouping-backslash ,@(funcall r 'string.escape))
      (font-lock-regexp-grouping-construct ,@(funcall r 'string.escape))
      (font-lock-number-face ,@(funcall r 'number))
      (font-lock-doc-face ,@(funcall r 'comment.doc))
      (font-lock-doc-markup-face ,@(funcall r 'comment.doc))
      (font-lock-comment-face ,@(funcall r 'comment))
      (font-lock-comment-delimiter-face ,@(funcall r 'comment))
      (font-lock-preprocessor-face ,@(funcall r 'preproc))
      (font-lock-operator-face ,@(funcall r 'operator))
      (font-lock-punctuation-face ,@(funcall r 'punctuation))
      (font-lock-bracket-face ,@(funcall r 'punctuation))
      (font-lock-delimiter-face ,@(funcall r 'punctuation))
      (font-lock-misc-punctuation-face ,@(funcall r 'punctuation))
      (font-lock-negation-char-face ,@(funcall r 'operator))
      (font-lock-warning-face :foreground ,warn :weight bold)
      (themer-reader-exit ,@(funcall r 'keyword.exit))
      (themer-reader-type-definition ,@(funcall r 'type.def))
      (themer-reader-module ,@(funcall r 'module))
      (themer-reader-meta ,@(funcall r 'attribute))
      (themer-reader-macro-call ,@(funcall r 'macro.call))
      (themer-reader-macro-definition ,@(funcall r 'macro.def))
      (themer-reader-todo ,@(funcall r 'comment.todo))
      ;; Only applied when `themer-reader-fade-commented-code' is set.
      (themer-reader-commented-code :foreground ,faded :weight normal
                                    :slant ,(if themer-reader-italic-comments 'italic 'normal))
      (themer-reader-parameter ,@(funcall r 'parameter))
      (themer-reader-module-variable ,@(plist-put (funcall r 'variable.def) :weight 'bold))
      (themer-reader-constant-definition ,@(funcall r 'constant.def))
      ;; Eglot semantic tokens.  Eglot puts its faces in front of the
      ;; tree-sitter ones, so a coloured eglot face hides the reader's finer
      ;; distinctions (exits, TODO, escapes, definitions in bold).  Only what
      ;; tree-sitter can't know is coloured: parameter uses, enum members,
      ;; macro uses, namespaces, deprecation.  The rest are left empty, the
      ;; tree-sitter face showing through.  Rust-analyzer also calls `u32'
      ;; and `derive' namespaces; `themer-reader--drop-namespace-tokens'
      ;; takes those off.
      ,@(when (facep 'eglot-semantic-namespace)
          `((eglot-semantic-parameter ,@(if (funcall tg :binding) (funcall r 'parameter) plain))
            (eglot-semantic-enumMember ,@(funcall r 'constant.use))
            (eglot-semantic-macro :foreground ,(plist-get (funcall r 'macro.call) :foreground))
            (eglot-semantic-decorator ,@(funcall r 'attribute))
            (eglot-semantic-namespace ,@(funcall r 'module))
            (eglot-semantic-deprecated :strike-through t)
            ,@(mapcar #'list
                      '(eglot-semantic-type eglot-semantic-class
                        eglot-semantic-enum eglot-semantic-interface eglot-semantic-struct
                        eglot-semantic-typeParameter eglot-semantic-variable
                        eglot-semantic-property eglot-semantic-event eglot-semantic-function
                        eglot-semantic-method eglot-semantic-keyword eglot-semantic-modifier
                        eglot-semantic-comment eglot-semantic-string eglot-semantic-number
                        eglot-semantic-regexp eglot-semantic-operator
                        eglot-semantic-declaration eglot-semantic-definition
                        eglot-semantic-readonly eglot-semantic-static eglot-semantic-abstract
                        eglot-semantic-async eglot-semantic-modification
                        eglot-semantic-documentation eglot-semantic-defaultLibrary))))
      ;; Diagnostics
      (flymake-error ,@(funcall wave err))
      (flymake-warning ,@(funcall wave warn))
      (flymake-note ,@(funcall wave (funcall loud 'callable)))
      (flycheck-error ,@(funcall wave err))
      (flycheck-warning ,@(funcall wave warn))
      (flycheck-info ,@(funcall wave (funcall loud 'callable)))
      (flycheck-fringe-error :foreground ,err)
      (flycheck-fringe-warning :foreground ,warn)
      (flycheck-fringe-info :foreground ,(funcall loud 'callable))
      (eglot-diagnostic-tag-unnecessary-face ,@(funcall r 'mod.unnecessary))
      (eglot-diagnostic-tag-deprecated-face :strike-through t)
      (eglot-highlight-symbol-face :background ,raised)
      (eglot-inlay-hint-face :foreground ,faded :height 0.8)
      (eglot-mode-line :foreground ,accent :weight bold)
      (compilation-error :foreground ,err :weight bold)
      (compilation-warning :foreground ,warn :weight bold)
      (compilation-info :foreground ,(funcall loud 'callable))
      (compilation-line-number :foreground ,dim)
      (compilation-column-number :foreground ,dim)
      (compilation-mode-line-fail :foreground ,err :weight bold)
      (compilation-mode-line-exit :foreground ,add :weight bold)
      (compilation-mode-line-run :foreground ,warn)
      (flymake-error-echo :foreground ,err)
      (flymake-warning-echo :foreground ,warn)
      (flymake-note-echo :foreground ,(funcall loud 'callable))
      ;; End-of-line diagnostics sit in the code: smaller, and in prose type.
      (flymake-end-of-line-diagnostics-face :foreground ,dim :height 0.9 ,@prose)
      (flymake-error-echo-at-eol :foreground ,err :height 0.9 ,@prose)
      (flymake-warning-echo-at-eol :foreground ,warn :height 0.9 ,@prose)
      (flymake-note-echo-at-eol :foreground ,(funcall loud 'callable) :height 0.9 ,@prose)
      (eglot-code-action-indicator-face :foreground ,warn :weight bold)
      ;; Diff
      (diff-added :background ,(funcall mix add 0.18) :extend t)
      (diff-removed :background ,(funcall mix rem 0.18) :extend t)
      (diff-changed :background ,(funcall mix warn 0.15) :extend t)
      (diff-refine-added :background ,(funcall mix add 0.38))
      (diff-refine-removed :background ,(funcall mix rem 0.38))
      (diff-refine-changed :background ,(funcall mix warn 0.32))
      (diff-indicator-added :foreground ,add)
      (diff-indicator-removed :foreground ,rem)
      (diff-indicator-changed :foreground ,warn)
      (diff-header :background ,subtle :extend t)
      (diff-file-header :background ,raised :weight bold :extend t)
      (diff-hunk-header :foreground ,accent :background ,subtle :extend t)
      (diff-context :foreground ,dim)
      (diff-hl-insert :foreground ,add :background ,(funcall mix add 0.18))
      (diff-hl-delete :foreground ,rem :background ,(funcall mix rem 0.18))
      (diff-hl-change :foreground ,warn :background ,(funcall mix warn 0.15))
      (magit-diff-added :foreground ,fg :background ,(funcall mix add 0.12) :extend t)
      (magit-diff-added-highlight :foreground ,fg :background ,(funcall mix add 0.18) :extend t)
      (magit-diff-removed :foreground ,fg :background ,(funcall mix rem 0.12) :extend t)
      (magit-diff-removed-highlight :foreground ,fg :background ,(funcall mix rem 0.18) :extend t)
      (magit-diff-context :foreground ,dim :extend t)
      (magit-diff-context-highlight :foreground ,dim :background ,subtle :extend t)
      (magit-diff-file-heading :weight bold :extend t)
      (magit-diff-file-heading-highlight :background ,raised :weight bold :extend t)
      (magit-diff-hunk-heading :foreground ,dim :background ,subtle :extend t)
      (magit-diffstat-added :foreground ,add)
      (magit-diffstat-removed :foreground ,rem)
      ;; Whitespace
      (whitespace-space :foreground ,border)
      (whitespace-tab :foreground ,border)
      (whitespace-newline :foreground ,border)
      (whitespace-trailing :background ,(funcall mix err 0.45))
      (whitespace-line :background ,(funcall mix warn 0.15))
      (whitespace-empty :background ,subtle)
      (whitespace-indentation :foreground ,border)
      (whitespace-space-before-tab :background ,(funcall mix warn 0.30))
      (whitespace-space-after-tab :background ,(funcall mix warn 0.30))
      ;; Completion
      (completions-common-part :foreground ,accent :weight bold)
      (completions-first-difference :weight bold)
      (completions-annotations :foreground ,dim)
      (completions-highlight :background ,raised)
      (vertico-current :background ,raised :extend t)
      (vertico-group-title :foreground ,dim)
      (vertico-group-separator :foreground ,faded :strike-through t)
      (corfu-default :foreground ,fg :background ,subtle)
      (corfu-current :background ,strong)
      (corfu-border :background ,border)
      (corfu-bar :background ,border)
      (corfu-annotations :foreground ,dim)
      (orderless-match-face-0 :foreground ,accent :weight bold)
      (orderless-match-face-1 :foreground ,(funcall loud 'value) :weight bold)
      (orderless-match-face-2 :foreground ,(funcall loud 'type) :weight bold)
      (orderless-match-face-3 :foreground ,(funcall loud 'syntax) :weight bold)
      (corfu-deprecated :foreground ,dim :strike-through t)
      (vertico-posframe-border :background ,border)
      (embark-target :background ,raised)
      (consult-preview-line :background ,subtle :extend t)
      ;; Completion annotations draw kinds as code does.
      (marginalia-function ,@(funcall r 'function.call))
      (marginalia-type ,@(funcall r 'type.use))
      (marginalia-documentation :foreground ,dim ,@prose)
      (which-key-separator-face :foreground ,dim)
      ;; Editor state
      (fill-column-indicator :foreground ,border)
      (mode-line-emphasis :weight bold)
      (dired-flagged :foreground ,err :weight bold)
      (dired-marked :foreground ,warn :weight bold)
      (dired-ignored :foreground ,dim)
      ;; Brackets are punctuation at every depth; only a broken pair stands out.
      ,@(mapcar (lambda (n) `(,(intern (format "rainbow-delimiters-depth-%d-face" n))
                              ,@(funcall r 'punctuation)))
                (number-sequence 1 9))
      (rainbow-delimiters-unmatched-face :foreground ,err :weight bold)
      (rainbow-delimiters-mismatched-face :foreground ,err :weight bold)
      ;; Org: TODO is the popout, as in code comments; metadata is dim, as
      ;; comments are; inline code and verbatim are values.
      (org-todo ,@(funcall r 'comment.todo))
      (org-done :foreground ,add :weight bold)
      (org-headline-done :foreground ,dim)
      (org-meta-line :foreground ,dim)
      (org-drawer :foreground ,dim)
      (org-special-keyword :foreground ,dim)
      (org-tag :foreground ,dim :weight normal)
      (org-document-info-keyword :foreground ,dim)
      (org-block :background ,subtle :extend t)
      (org-block-begin-line :foreground ,dim :background ,subtle :extend t)
      (org-block-end-line :inherit org-block-begin-line)
      (org-quote :background ,subtle :extend t)
      (org-code ,@(funcall r 'constant.use))
      (org-verbatim ,@(funcall r 'string))
      ;; Heading levels below the first step through the families' loud
      ;; colours (org-level-N inherit outline-N).
      ,@(cl-loop for n from 2 to 8
                 for louds = (mapcar #'cdr (funcall tg :loud))
                 collect `(,(intern (format "outline-%d" n))
                           :foreground ,(nth (mod (- n 2) (length louds)) louds)
                           :weight bold))
      ;; Terminal colours (term and vterm faces inherit these).
      ,@(cl-loop for (name normal . bright) in (themer-reader--ansi tiers)
                 collect `(,(intern (format "ansi-color-%s" name))
                           :foreground ,normal :background ,normal)
                 collect `(,(intern (format "ansi-color-bright-%s" name))
                           :foreground ,bright :background ,bright))
      ;; The UI accent (`:accent'): chrome only, never a syntax face.
      (marginalia-key :foreground ,accent)
      (consult-highlight-match :foreground ,accent :weight bold)
      (embark-keybinding :foreground ,accent :weight bold)
      (which-key-key-face :foreground ,accent :weight bold)
      (doom-modeline-bar :background ,accent)
      (magit-section-heading :foreground ,accent :weight bold)
      (magit-diff-hunk-heading-highlight :foreground ,accent :background ,raised :extend t)
      (org-document-title :foreground ,accent :weight bold :height 1.3)
      (org-checkbox :foreground ,accent :weight bold)
      (org-agenda-structure :foreground ,accent :weight bold)
      (org-agenda-date-today :foreground ,accent :weight bold)
      (org-level-1 :foreground ,accent :weight bold :height 1.15)
      (outline-1 :foreground ,accent :weight bold)
      (dired-header :foreground ,accent :weight bold)
      (eshell-prompt :foreground ,accent :weight bold))))

;;;; Defining themes

(defun themer-reader--face-specs (derived)
  "`custom-theme-set-faces' arguments for DERIVED."
  (mapcar (lambda (f) `(,(car f) ((t ,@(cdr f))))) (themer-reader-faces derived)))

(defun themer-reader-define (name spec)
  "Derive SPEC and apply it as the faces of theme NAME."
  (let ((derived (themer-reader-derive spec)))
    (put name 'themer-reader-spec spec)
    (put name 'themer-reader-derived derived)
    (apply #'custom-theme-set-faces name (themer-reader--face-specs derived))
    (when themer-reader-enable-rules
      (themer-reader-treesit-mode 1))
    derived))

;;;###autoload
(defmacro themer-reader-deftheme (name doc &rest spec)
  "Define reader theme NAME with docstring DOC from SPEC.
SPEC is a plist of colours, each a \"#rrggbb\" string or the name of a
palette entry:
  :palette ((NAME \"#rrggbb\") ...)
                       optional named colours, in order; not evaluated
  :bg :fg              background and default ink
  :syntax :callable :type :value :meta
                       one accent per kind family (:type and :meta may be
                       omitted: their roles fall back as in reduced
                       conformance)
  :binding             optional quiet parameter tint
  :popout              optional TODO ink (default: an unused fixed colour)
  :accent              optional UI accent for the chrome (cursor, prompts,
                       matches, headings), never for syntax; default
                       :popout, else the callable loud colour
  :error :warning :added :removed
                       fixed conventions (defaults derived from :bg)
A symbol value names a palette entry and is not evaluated; other
values are.  Use it in NAME-theme.el; it also provides the theme."
  (declare (indent 2) (doc-string 2))
  `(progn
     (deftheme ,name ,doc)
     (themer-reader-define ',name (list ,@(themer-reader--quote-spec spec)))
     (provide-theme ',name)))

(defun themer-reader--literal-p (key value)
  "Non-nil if VALUE of spec KEY is taken as written, not evaluated.
That is the :palette list and palette names."
  (or (eq key :palette) (themer-reader-palette-name-p value)))

(defun themer-reader--quote-spec (spec)
  "SPEC, a plist as written, with its literal values quoted."
  (cl-loop for (k v) on spec by #'cddr
           append (list k (if (themer-reader--literal-p k v) (list 'quote v) v))))

;;;; Tree-sitter rules

(defconst themer-reader--comment-nodes
  '((python "comment") (javascript "comment") (typescript "comment") (tsx "comment")
    (rust "line_comment" "block_comment") (go "comment") (c "comment") (cpp "comment")
    (java "line_comment" "block_comment") (lua "comment") (bash "comment"))
  "Comment node types per language.")

(defconst themer-reader--exit-keywords
  '((python "return" "raise" "yield" "break" "continue")
    (javascript "return" "throw" "yield" "break" "continue")
    (typescript "return" "throw" "yield" "break" "continue")
    (tsx "return" "throw" "yield" "break" "continue")
    (rust "return" "break" "continue" "yield")
    (go "return" "break" "continue" "goto")
    (c "return" "break" "continue" "goto")
    (cpp "return" "break" "continue" "goto" "throw" "co_return" "co_yield")
    (java "return" "throw" "yield" "break" "continue")
    (lua "return" "break" "goto"))
  "Exit keywords per language, as anonymous nodes.")

(defconst themer-reader--rules
  '((python
     (type-definition (class_definition name: (identifier) @themer-reader-type-definition))
     (meta (decorator "@" @themer-reader-meta)
           (decorator (identifier) @themer-reader-meta)
           (decorator (attribute) @themer-reader-meta)
           (decorator (call function: (_) @themer-reader-meta)))
     (parameter (parameters (identifier) @themer-reader-parameter)
                (typed_parameter (identifier) @themer-reader-parameter)
                (default_parameter name: (identifier) @themer-reader-parameter)
                (typed_default_parameter name: (identifier) @themer-reader-parameter))
     (binding (assignment left: (identifier) @themer-reader--fontify-caps)
              (assignment left: (pattern_list (identifier) @themer-reader--fontify-caps))
              (assignment left: (tuple_pattern (identifier) @themer-reader--fontify-caps))))
    (javascript
     (type-definition (class_declaration name: (identifier) @themer-reader-type-definition))
     (meta (decorator "@" @themer-reader-meta (identifier) @themer-reader-meta)
           (decorator (call_expression function: (identifier) @themer-reader-meta)))
     (parameter (formal_parameters (identifier) @themer-reader-parameter))
     (binding (variable_declarator name: (_) @themer-reader--fontify-js-declarator)))
    (typescript
     (type-definition (class_declaration name: (type_identifier) @themer-reader-type-definition)
                      (abstract_class_declaration name: (type_identifier) @themer-reader-type-definition)
                      (interface_declaration name: (type_identifier) @themer-reader-type-definition)
                      (type_alias_declaration name: (type_identifier) @themer-reader-type-definition)
                      (enum_declaration name: (identifier) @themer-reader-type-definition))
     (meta (decorator "@" @themer-reader-meta (identifier) @themer-reader-meta)
           (decorator (call_expression function: (identifier) @themer-reader-meta)))
     (parameter (required_parameter pattern: (identifier) @themer-reader-parameter)
                (optional_parameter pattern: (identifier) @themer-reader-parameter))
     (binding (variable_declarator name: (_) @themer-reader--fontify-js-declarator)))
    (tsx
     (type-definition (class_declaration name: (type_identifier) @themer-reader-type-definition)
                      (abstract_class_declaration name: (type_identifier) @themer-reader-type-definition)
                      (interface_declaration name: (type_identifier) @themer-reader-type-definition)
                      (type_alias_declaration name: (type_identifier) @themer-reader-type-definition)
                      (enum_declaration name: (identifier) @themer-reader-type-definition))
     (meta (decorator "@" @themer-reader-meta (identifier) @themer-reader-meta)
           (decorator (call_expression function: (identifier) @themer-reader-meta)))
     (parameter (required_parameter pattern: (identifier) @themer-reader-parameter)
                (optional_parameter pattern: (identifier) @themer-reader-parameter))
     (binding (variable_declarator name: (_) @themer-reader--fontify-js-declarator)))
    (rust
     (rust-try (try_expression "?" @themer-reader-exit))
     (type-definition (struct_item name: (type_identifier) @themer-reader-type-definition)
                      (enum_item name: (type_identifier) @themer-reader-type-definition)
                      (union_item name: (type_identifier) @themer-reader-type-definition)
                      (type_item name: (type_identifier) @themer-reader-type-definition)
                      (trait_item name: (type_identifier) @themer-reader-type-definition))
     (meta (attribute_item) @themer-reader-meta
           (inner_attribute_item) @themer-reader-meta)
     (macro (macro_invocation macro: (identifier) @themer-reader-macro-call "!" @themer-reader-macro-call)
            (macro_invocation macro: (scoped_identifier name: (identifier) @themer-reader-macro-call))
            (macro_definition name: (identifier) @themer-reader-macro-definition))
     (module (scoped_identifier path: (identifier) @themer-reader--fontify-rust-module)
             (scoped_identifier path: (scoped_identifier name: (identifier) @themer-reader--fontify-rust-module))
             (scoped_type_identifier path: (identifier) @themer-reader--fontify-rust-module)
             (scoped_type_identifier path: (scoped_identifier name: (identifier) @themer-reader--fontify-rust-module))
             (scoped_use_list path: (identifier) @themer-reader--fontify-rust-module)
             (scoped_use_list path: (scoped_identifier name: (identifier) @themer-reader--fontify-rust-module))
             (use_wildcard (identifier) @themer-reader--fontify-rust-module)
             (mod_item name: (identifier) @themer-reader-module))
     (parameter (parameter pattern: (identifier) @themer-reader-parameter))
     (binding (const_item name: (identifier) @themer-reader--fontify-constant)
              (static_item name: (identifier) @themer-reader--fontify-rust-static)))
    (go
     (type-definition (type_spec name: (type_identifier) @themer-reader-type-definition)
                      (type_alias name: (type_identifier) @themer-reader-type-definition))
     (parameter (parameter_declaration name: (identifier) @themer-reader-parameter)
                (variadic_parameter_declaration name: (identifier) @themer-reader-parameter))
     (binding (const_spec (identifier) @themer-reader--fontify-constant)
              (var_spec (identifier) @themer-reader--fontify-module-variable)))
    (c
     (type-definition (struct_specifier name: (type_identifier) @themer-reader-type-definition body: (_))
                      (union_specifier name: (type_identifier) @themer-reader-type-definition body: (_))
                      (enum_specifier name: (type_identifier) @themer-reader-type-definition body: (_))
                      (type_definition declarator: (type_identifier) @themer-reader-type-definition))
     (macro (preproc_def name: (identifier) @themer-reader-macro-definition)
            (preproc_function_def name: (identifier) @themer-reader-macro-definition))
     (parameter (parameter_declaration declarator: (identifier) @themer-reader-parameter)
                (parameter_declaration declarator: (pointer_declarator declarator: (identifier) @themer-reader-parameter)))
     (binding (declaration) @themer-reader--fontify-c-declaration
              (preproc_def name: (identifier) @themer-reader--fontify-constant value: (_))))
    (cpp
     (type-definition (struct_specifier name: (type_identifier) @themer-reader-type-definition body: (_))
                      (class_specifier name: (type_identifier) @themer-reader-type-definition body: (_))
                      (union_specifier name: (type_identifier) @themer-reader-type-definition body: (_))
                      (enum_specifier name: (type_identifier) @themer-reader-type-definition body: (_))
                      (type_definition declarator: (type_identifier) @themer-reader-type-definition)
                      (alias_declaration name: (type_identifier) @themer-reader-type-definition))
     (meta (attribute_declaration) @themer-reader-meta)
     (macro (preproc_def name: (identifier) @themer-reader-macro-definition)
            (preproc_function_def name: (identifier) @themer-reader-macro-definition))
     (parameter (parameter_declaration declarator: (identifier) @themer-reader-parameter)
                (parameter_declaration declarator: (reference_declarator (identifier) @themer-reader-parameter))
                (parameter_declaration declarator: (pointer_declarator declarator: (identifier) @themer-reader-parameter)))
     (binding (declaration) @themer-reader--fontify-c-declaration
              (preproc_def name: (identifier) @themer-reader--fontify-constant value: (_))))
    (java
     (type-definition (class_declaration name: (identifier) @themer-reader-type-definition)
                      (interface_declaration name: (identifier) @themer-reader-type-definition)
                      (enum_declaration name: (identifier) @themer-reader-type-definition)
                      (record_declaration name: (identifier) @themer-reader-type-definition)
                      (annotation_type_declaration name: (identifier) @themer-reader-type-definition))
     (meta (marker_annotation "@" @themer-reader-meta name: (_) @themer-reader-meta)
           (annotation "@" @themer-reader-meta name: (_) @themer-reader-meta))
     (parameter (formal_parameter name: (identifier) @themer-reader-parameter))
     (binding (field_declaration declarator: (variable_declarator name: (identifier) @themer-reader--fontify-java-field))
              (constant_declaration declarator: (variable_declarator name: (identifier) @themer-reader--fontify-constant))))
    (lua
     (exit-statements (break_statement) @themer-reader-exit
                      (goto_statement "goto" @themer-reader-exit))
     (parameter (parameters (identifier) @themer-reader-parameter))
     (binding (variable_list name: (identifier) @themer-reader--fontify-lua-variable)))
    (bash
     (exit ((command_name (word) @themer-reader-exit)
            (:match "\\`\\(?:return\\|exit\\|break\\|continue\\)\\'" @themer-reader-exit)))
     (binding (variable_assignment name: (variable_name) @themer-reader--fontify-bash-variable))))
  "Per language: (GROUP QUERY...) rule groups, each compiled on its own.")

(defun themer-reader--queries (lang)
  "Alist (GROUP . QUERY) of every rule group for LANG."
  (append
   ;; Only the keywords this grammar version has as anonymous nodes.
   (when-let* ((kws (cl-remove-if
                     (lambda (k) (and (treesit-language-available-p lang)
                                      (themer-reader--query-ok lang `([,k] @themer-reader-exit))))
                     (alist-get lang themer-reader--exit-keywords))))
     (list (cons 'exit `([,@kws] @themer-reader-exit))))
   (mapcar (lambda (g) (cons (car g) (cdr g)))
           (alist-get lang themer-reader--rules))
   (when-let* ((nodes (alist-get lang themer-reader--comment-nodes)))
     (list (cons 'comment `([,@(mapcar (lambda (n) (list (intern n))) nodes)]
                            @themer-reader--fontify-comment))))))

(defun themer-reader--query-ok (lang query)
  "Nil if QUERY compiles for LANG, else the error message."
  (condition-case err
      (progn (treesit-query-compile lang query t) nil)
    (error (error-message-string err))))

(defvar themer-reader--settings-cache nil
  "Alist LANG -> font-lock settings, or :none when the grammar is missing.")

(defun themer-reader--settings (lang)
  "Font-lock settings for LANG; groups whose query fails are skipped."
  (let ((cached (alist-get lang themer-reader--settings-cache :unset)))
    (if (not (eq cached :unset))
        (unless (eq cached :none) cached)
      (let ((settings
             (when (treesit-language-available-p lang)
               (cl-loop for (group . query) in (themer-reader--queries lang)
                        for bad = (themer-reader--query-ok lang query)
                        if bad do (message "themer-reader: skipping %s %s rules: %s" lang group bad)
                        else append (treesit-font-lock-rules
                                     :language lang :feature 'themer-reader :override t
                                     query)))))
        (setf (alist-get lang themer-reader--settings-cache) (or settings :none))
        settings))))

(defconst themer-reader--cc-decl
  (concat "\\(?:\\(?:local\\|let\\|const\\|var\\|mut\\|static\\|final\\|auto\\|int\\|long\\|char"
          "\\|float\\|double\\|bool\\|string\\|String\\|def\\|val\\|my\\|our\\)[[:space:]]+\\)\\{0,2\\}"))

(defconst themer-reader--cc-regexps
  `((mark . "\\`[[:space:]]*\\(?:/\\{2,\\}\\|#:\\|#+\\|--+\\|;+\\|\\*+\\|<!--\\|/\\*+\\|%+\\)[[:space:]]?")
    (tail . "[[:space:]]*\\(?:\\*/\\|-->\\|]]\\|=]\\)[[:space:]]*\\'")
    (ruler . "[[:space:]]*[-;=*#~_/]\\{3,\\}[[:space:]]*\\'")
    (sentence . "\\(?:\\`\\|[^[:alnum:]_']\\)[A-Za-z]+\\(?:[ \t]+[A-Za-z]+\\)\\{3,\\}\\(?:[^[:alnum:]_]\\|\\'\\)")
    (directive . ,(concat "\\`\\(?:#\\|shellcheck\\|noqa\\|pylint\\|eslint\\|istanbul\\|nolint\\|flake8"
                          "\\|prettier-ignore\\|clang-format\\|type:\\|pragma\\|go:\\|NOLINT\\|c8 "
                          "\\|coding[:=]\\|-\\*-\\)"))
    (call . "\\`[A-Za-z_$][[:alnum:]_$]*\\(?:\\.[A-Za-z_$][[:alnum:]_$]*\\)*(")
    (paren-kw . "\\`\\(?:if\\|for\\|while\\|switch\\|return\\|else if\\|elif\\|catch\\)[[:space:]]?(")
    (assign . ,(concat "\\`" themer-reader--cc-decl
                       "[A-Za-z_$][][[:alnum:]_$.]*[[:space:]]*"
                       "\\(?:[-+*/|&^%]?=\\(?:[^=[:space:]]\\|[[:space:]]+[^[:space:]]\\)"
                       "\\|:=[[:space:]]*[^[:space:]]\\)"))
    (multi . "\\`[][[:alnum:]_$.]+\\(?:[[:space:]]*,[[:space:]]*[][[:alnum:]_$.]+\\)+[[:space:]]*:?=")
    (stmt . "\\`\\(?:return\\|throw\\|raise\\|yield\\|await\\|assert\\|require\\|let\\|const\\|var\\|local\\)\\(\\(?:[^[:alnum:]_].*\\)?\\)\\'")
    (lisp . ,(concat "\\`(\\(?:defun\\|defvar\\|defcustom\\|setq\\|let\\*?\\|when\\|unless\\|cond"
                     "\\|progn\\|require\\|use-package\\|[a-z]+-[[:alnum:]_-]+\\)[[:space:])]")))
  "Regexps of the commented-out code heuristic (harness role_tokens.py).")

(defun themer-reader--cc (name s &optional start)
  "Match regexp NAME of `themer-reader--cc-regexps' against S from START."
  (let ((case-fold-search nil))
    (string-match (alist-get name themer-reader--cc-regexps) s start)))

(defun themer-reader--code-line-p (body)
  "Non-nil if comment line BODY, marker stripped, looks like code."
  (let* ((case-fold-search nil)
         (b (string-trim body))
         (b (if (themer-reader--cc 'ruler b) (substring b 0 (match-beginning 0)) b)))
    (cond
     ((or (string-empty-p b) (string-match-p "\\`[-=*#~_/ ]+\\'" b)) nil)
     ((or (string-match-p "\\`\\(?:http://\\|https://\\|!\\|TODO\\|FIXME\\|XXX\\|NOTE\\|HACK\\|BUG\\)" b)
          (themer-reader--cc 'directive b))
      nil)
     ((or (string-search "://" b) (themer-reader--cc 'sentence b)
          (string-match-p "\\`\\(?:e\\.g\\|i\\.e\\|defined(\\)" b))
      nil)
     ((let ((first (and (string-match "\\`[A-Za-z_]+" b) (match-string 0 b))))
        (and first
             (member first '("if" "elif" "else" "for" "while" "try" "except" "finally"
                             "def" "class" "with" "match"))
             (string-suffix-p ":" b)
             (or (member first '("else" "try" "finally"))
                 (string-match-p "[]()=<>.[]" b))))
      t)
     ((or (themer-reader--cc 'paren-kw b) (themer-reader--cc 'assign b)
          (themer-reader--cc 'multi b) (themer-reader--cc 'lisp b))
      t)
     ((themer-reader--cc 'call b)
      (or (and (memq (aref b (1- (length b))) '(?\) ?\; ?{ ?} ?,))
               (not (string-match-p "\\`[[:alnum:]_$.]+()\\'" b)))
          (> (cl-count ?\( b) (cl-count ?\) b))))
     ((and (themer-reader--cc 'stmt b)
           (string-match-p "[(=[{]\\|[[:alnum:]_]\\.[[:alnum:]_]\\|::" (match-string 1 b)))
      t)
     (t (let ((last (aref b (1- (length b)))))
          (and (memq last '(?\; ?{ ?}))
               (or (/= last ?\;) (not (<= ?0 (aref b 0) ?9)))))))))

(defun themer-reader-commented-code-p (text)
  "Non-nil if comment TEXT looks like commented-out code.
The draft 3.2 `comment.code' heuristic, as tightened in the research
harness (role_tokens.py `is_commented_code'): a line looks like code when
it ends like a statement or starts like an assignment, call or block
header, and has no run of four alphabetic words.  Doc comments and URLs
never count; a multi-line comment counts when 60% of its lines do."
  (let ((tt (string-trim text)))
    (with-syntax-table (standard-syntax-table)
      (unless (string-match-p "\\`\\(?:/\\*\\*\\|/\\*!\\|///\\|//!\\|#!\\)" tt)
        (let* ((lines (mapcar (lambda (ln)
                                (let ((ln (if (themer-reader--cc 'mark ln) (substring ln (match-end 0)) ln)))
                                  (if (themer-reader--cc 'tail ln) (substring ln 0 (match-beginning 0)) ln)))
                              (split-string tt "\n")))
               (lines (cl-remove-if (lambda (ln) (string-empty-p (string-trim ln))) lines))
               (hits (cl-count-if #'themer-reader--code-line-p lines)))
          (and lines (> hits 0) (>= hits (* 0.6 (length lines)))))))))

(defun themer-reader--fontify-comment (node override start end &rest _)
  "Fontify comment NODE: TODO markers, and code-like comments.
The whole comment is faded when it looks like code and
`themer-reader-fade-commented-code' is set.  OVERRIDE, START and END are as
for tree-sitter font-lock functions."
  (let ((beg (treesit-node-start node))
        (fin (treesit-node-end node)))
    (when (and themer-reader-fade-commented-code
               (themer-reader-commented-code-p (treesit-node-text node t)))
      (treesit-fontify-with-override beg fin 'themer-reader-commented-code override start end))
    (save-excursion
      (goto-char beg)
      (let ((case-fold-search nil))
        (while (re-search-forward "\\_<\\(?:TODO\\|FIXME\\|XXX\\)\\_>" fin t)
          (treesit-fontify-with-override (match-beginning 0) (match-end 0)
                                         'themer-reader-todo override start end))))))

;;;; Module paths

(defun themer-reader--fontify-rust-module (node override start end &rest _)
  "Module face on NODE, a Rust path segment, unless it names a type.
Capitalised segments are types (`Config::new'), as are primitives
\(`u32::MAX'); `rust-ts-mode' draws the rest in the constant face.
OVERRIDE, START and END as usual."
  (let ((case-fold-search nil) (text (treesit-node-text node t)))
    (unless (or (string-match-p "\\`[A-Z]" text)
                (string-match-p "\\`\\(?:[iu]\\(?:8\\|16\\|32\\|64\\|128\\|size\\)\\|f32\\|f64\\|bool\\|char\\|str\\)\\'" text))
      (treesit-fontify-with-override (treesit-node-start node) (treesit-node-end node)
                                     'themer-reader-module override start end))))

;;;; Module-level bindings and constant definitions
;;
;; The standard draws module-level variable bindings in bold default ink
;; (locals stay plain) and constant definitions in the value family,
;; strong.  "Top level" is as in the research corpus (role_tokens.py
;; `enclosing_func'): not inside a function, method, lambda or closure;
;; class bodies, namespaces and top-level blocks count as top level.
;; Constants follow its `decl_class':
;;
;;   language    module variable (top level only)   constant definition
;;   ----------  ---------------------------------  ---------------------------------
;;   python      assignment targets                 ALL_CAPS assignment targets at
;;               (incl. class bodies)               top level
;;   js, ts,     let/var declarators; const ones    top-level const declarators named
;;   tsx         not named ALL_CAPS                 ALL_CAPS
;;   rust        static mut items                   const items, non-mut static items
;;                                                  (any scope)
;;   go          var specs                          const specs (any scope)
;;   c, c++      file/namespace-scope declarators   top-level declarations with a
;;               (not prototypes)                   const/constexpr qualifier (not a
;;                                                  pointer to const); object-like
;;                                                  #define with a value
;;   java        -- (fields are fields)             static final fields, interface
;;                                                  constants
;;   lua         local and global assignments       local NAME <const>/<close> at top
;;                                                  level
;;   bash        assignments, export, declare       readonly or declare -r at top
;;                                                  level
;;
;; ALL_CAPS is the research's test: _?[A-Z][A-Z0-9_]+.  A JS/TS declarator
;; whose value is a function (const f = () => ...) is drawn as a function
;; definition, at any scope, and a binding the major mode already drew as a
;; function definition keeps that face.  An object-like #define with no value (include guards, feature
;; flags) stays a macro definition; one with a value is a named constant.

(defconst themer-reader--function-nodes
  '("function_definition" "function_declaration" "function_item" "function_expression"
    "function" "arrow_function" "method_definition" "method_declaration"
    "constructor_declaration" "compact_constructor_declaration" "lambda"
    "lambda_expression" "closure_expression" "func_literal" "generator_function"
    "generator_function_declaration" "static_initializer" "macro_definition")
  "Node types that make a binding local (role_tokens.py `FUNC_TYPES').")

(defun themer-reader--top-level-p (node)
  "Non-nil if NODE is not inside a function, method, lambda or closure."
  (let ((p (treesit-node-parent node)) (top t))
    (while (and p top)
      (if (member (treesit-node-type p) themer-reader--function-nodes)
          (setq top nil)
        (setq p (treesit-node-parent p))))
    top))

(defun themer-reader--caps-p (name)
  "Non-nil if NAME is ALL_CAPS (role_stats.py `CAPS')."
  (let ((case-fold-search nil))
    (string-match-p "\\`_?[A-Z][A-Z0-9_]+\\'" name)))

(defun themer-reader--bind (node face override start end)
  "Fontify NODE with FACE, as tree-sitter font-lock does with OVERRIDE.
START and END bound the region.  A function definition face is kept."
  (let* ((beg (treesit-node-start node))
         (old (get-text-property beg 'face)))
    (unless (or (eq old 'font-lock-function-name-face)
                (and (consp old) (memq 'font-lock-function-name-face old)))
      (treesit-fontify-with-override beg (treesit-node-end node) face override start end))))

(defun themer-reader--fontify-module-variable (node override start end &rest _)
  "Module-variable face on NODE at top level.  OVERRIDE, START, END as usual."
  (when (themer-reader--top-level-p node)
    (themer-reader--bind node 'themer-reader-module-variable override start end)))

(defun themer-reader--fontify-constant (node override start end &rest _)
  "Constant-definition face on NODE.  OVERRIDE, START, END as usual."
  (themer-reader--bind node 'themer-reader-constant-definition override start end))

(defun themer-reader--fontify-caps (node override start end &rest _)
  "At top level, constant face on NODE if ALL_CAPS, else module variable.
OVERRIDE, START and END as usual."
  (when (themer-reader--top-level-p node)
    (themer-reader--bind node (if (themer-reader--caps-p (treesit-node-text node t))
                                  'themer-reader-constant-definition
                                'themer-reader-module-variable)
                         override start end)))

(defun themer-reader--fontify-js-declarator (node override start end &rest _)
  "NODE is a JS/TS declarator name: an identifier or a destructuring pattern.
OVERRIDE, START and END as usual."
  (if (member (treesit-node-type (treesit-node-child-by-field-name (treesit-node-parent node) "value"))
              themer-reader--function-nodes)
      ;; const f = () => ...: a function definition, wherever it is.
      (themer-reader--bind node 'font-lock-function-name-face override start end)
    (when (themer-reader--top-level-p node)
      (let* ((decl (treesit-node-parent (treesit-node-parent node)))
             (const (and decl (equal (treesit-node-type decl) "lexical_declaration")
                         (equal (treesit-node-type (treesit-node-child decl 0)) "const")))
             (names (if (equal (treesit-node-type node) "identifier")
                        (list node)
                      (treesit-filter-child
                       node (lambda (c) (member (treesit-node-type c)
                                                '("identifier" "shorthand_property_identifier_pattern")))
                       t))))
        (dolist (n names)
          (themer-reader--bind n (if (and const (themer-reader--caps-p (treesit-node-text n t)))
                                     'themer-reader-constant-definition
                                   'themer-reader-module-variable)
                               override start end))))))

(defun themer-reader--fontify-rust-static (node override start end &rest _)
  "NODE names a Rust static: a constant unless `mut'.
OVERRIDE, START and END as usual."
  (if (treesit-filter-child (treesit-node-parent node)
                            (lambda (c) (equal (treesit-node-type c) "mutable_specifier")))
      (themer-reader--fontify-module-variable node override start end)
    (themer-reader--fontify-constant node override start end)))

(defun themer-reader--c-declarator-name (decl)
  "Identifier named by C declarator DECL and whether it passes a pointer.
Return (NODE . POINTER-P), or nil for function declarators."
  (let ((ptr nil))
    (while (and decl (not (member (treesit-node-type decl) '("identifier" "function_declarator"))))
      (when (equal (treesit-node-type decl) "pointer_declarator") (setq ptr t))
      (setq decl (or (treesit-node-child-by-field-name decl "declarator")
                     (treesit-node-child decl 0 t))))
    (when (and decl (equal (treesit-node-type decl) "identifier"))
      (cons decl ptr))))

(defun themer-reader--fontify-c-declaration (node override start end &rest _)
  "NODE is a C/C++ declaration; fontify its names at file or namespace scope.
OVERRIDE, START and END as usual."
  (when (themer-reader--top-level-p node)
    (let ((const (treesit-filter-child
                  node (lambda (c) (and (equal (treesit-node-type c) "type_qualifier")
                                        (member (treesit-node-text c t) '("const" "constexpr")))))))
      (dotimes (i (treesit-node-child-count node))
        (when (equal (treesit-node-field-name-for-child node i) "declarator")
          (pcase (themer-reader--c-declarator-name (treesit-node-child node i))
            (`(,id . ,ptr)
             (themer-reader--bind id (if (and const (not ptr))
                                         'themer-reader-constant-definition
                                       'themer-reader-module-variable)
                                  override start end))))))))

(defun themer-reader--fontify-java-field (node override start end &rest _)
  "NODE names a Java field: a constant when static final.
OVERRIDE, START and END as usual."
  (when-let* ((field (treesit-node-parent (treesit-node-parent node)))
              (mods (car (treesit-filter-child
                          field (lambda (c) (equal (treesit-node-type c) "modifiers")))))
              (text (treesit-node-text mods t))
              ((string-match-p "\\_<static\\_>" text))
              ((string-match-p "\\_<final\\_>" text)))
    (themer-reader--fontify-constant node override start end)))

(defun themer-reader--fontify-lua-variable (node override start end &rest _)
  "NODE is a Lua assignment target.  OVERRIDE, START and END as usual."
  (when (themer-reader--top-level-p node)
    (let ((attr (treesit-node-next-sibling node t)))
      (themer-reader--bind node (if (and attr (equal (treesit-node-type attr) "attribute")
                                         (string-match-p "\\_<\\(?:const\\|close\\)\\_>"
                                                         (treesit-node-text attr t)))
                                    'themer-reader-constant-definition
                                  'themer-reader-module-variable)
                           override start end))))

(defun themer-reader--fontify-bash-variable (node override start end &rest _)
  "NODE names a bash assignment.  OVERRIDE, START and END as usual."
  (let* ((asg (treesit-node-parent node))
         (cmd (treesit-node-parent asg)))
    (when (and (themer-reader--top-level-p node)
               ;; FOO=1 cmd sets the command's environment, not a binding.
               (not (equal (treesit-node-type cmd) "command")))
      (themer-reader--bind
       node (if (and (equal (treesit-node-type cmd) "declaration_command")
                     (string-match-p "\\`\\(?:readonly\\|\\(?:declare\\|typeset\\)[ \t]+-[[:alpha:]]*r\\)"
                                     (treesit-node-text cmd t)))
                'themer-reader-constant-definition
              'themer-reader-module-variable)
       override start end))))

(defconst themer-reader--languages
  '(python javascript typescript tsx rust go c cpp java lua bash)
  "Languages `themer-reader-treesit-mode' adds rules for.")

(defun themer-reader--buffer-language ()
  "The language of this buffer's primary tree-sitter parser, or nil."
  (when-let* ((parser (or (and (boundp 'treesit-primary-parser)
                               (symbol-value 'treesit-primary-parser))
                          (car (treesit-parser-list)))))
    (treesit-parser-language parser)))

;;;; Semantic-token fix-up
;;
;; Rust-analyzer calls primitives (`u32', `str') and `derive' namespaces as
;; well as modules.  Where tree-sitter has drawn a type or an attribute,
;; the namespace face comes off again.  The fix-up is a font-lock keyword
;; after eglot's, re-appended (by a buffer-local hook) whenever eglot's
;; semantic tokens start.

(defconst themer-reader--not-namespace-faces '(font-lock-type-face themer-reader-meta)
  "Tree-sitter faces that overrule an `eglot-semantic-namespace' token.")

(defun themer-reader--installed-p ()
  "Non-nil if the reader rules are in this buffer."
  (and (bound-and-true-p treesit-font-lock-settings)
       (cl-some (lambda (s) (eq (nth 2 s) 'themer-reader)) treesit-font-lock-settings)))

(defun themer-reader--drop-namespace-tokens (beg end &optional object)
  "Take `eglot-semantic-namespace' off BEG..END of OBJECT where it is mislabelled.
That is, where the face also has one of `themer-reader--not-namespace-faces'."
  (let ((p beg))
    (while (< p end)
      (let ((next (next-single-property-change p 'face object end))
            (face (get-text-property p 'face object)))
        (when (and (consp face) (memq 'eglot-semantic-namespace face)
                   (cl-some (lambda (f) (memq f face)) themer-reader--not-namespace-faces))
          (let ((rest (remq 'eglot-semantic-namespace face)))
            (put-text-property p next 'face (if (cdr rest) rest (car rest)) object)))
        (setq p next)))))

(defun themer-reader--semtok-fixup (limit)
  "Font-lock matcher: drop mislabelled namespace tokens from point to LIMIT."
  (themer-reader--drop-namespace-tokens (point) limit)
  nil)

(defun themer-reader--semtok-order ()
  "Put the namespace fix-up last in this buffer's font-lock keywords."
  (when (themer-reader--installed-p)
    (font-lock-remove-keywords nil '((themer-reader--semtok-fixup)))
    (font-lock-add-keywords nil '((themer-reader--semtok-fixup)) 'append)))

(defun themer-reader--install ()
  "Add the reader rules to this tree-sitter buffer and refontify."
  (when-let* (((bound-and-true-p treesit-font-lock-settings))
              (lang (themer-reader--buffer-language))
              ((memq lang themer-reader--languages))
              ((not (themer-reader--installed-p)))
              (settings (themer-reader--settings lang)))
    (setq-local treesit-font-lock-settings (append treesit-font-lock-settings
                                                   (copy-tree settings)))
    (setq-local treesit-font-lock-feature-list
                (cons (append (car treesit-font-lock-feature-list) '(themer-reader))
                      (cdr treesit-font-lock-feature-list)))
    (treesit-font-lock-recompute-features)
    (themer-reader--semtok-order)
    (add-hook 'eglot-semantic-tokens-mode-hook #'themer-reader--semtok-order nil t)
    (font-lock-flush)))

(defun themer-reader--uninstall ()
  "Remove the reader rules from this buffer and refontify."
  (when (themer-reader--installed-p)
    (setq-local treesit-font-lock-settings
                (cl-remove-if (lambda (s) (eq (nth 2 s) 'themer-reader)) treesit-font-lock-settings))
    (setq-local treesit-font-lock-feature-list
                (mapcar (lambda (l) (remq 'themer-reader l)) treesit-font-lock-feature-list))
    (treesit-font-lock-recompute-features)
    (font-lock-remove-keywords nil '((themer-reader--semtok-fixup)))
    (remove-hook 'eglot-semantic-tokens-mode-hook #'themer-reader--semtok-order t)
    (font-lock-flush)))

;;;###autoload
(define-minor-mode themer-reader-treesit-mode
  "Add reader-standard tree-sitter rules to tree-sitter major modes.
For python, javascript, typescript, tsx, rust, go, c, c++, java, lua and
bash, where the grammar is installed: exits (return, raise/throw, break,
continue, yield, goto, Rust `?') in `themer-reader-exit', type definition
names, Rust module paths, decorators and attributes, macro calls,
parameter declarations, module-level bindings and constant definitions,
TODO/FIXME/XXX in comments, and commented-out code when
`themer-reader-fade-commented-code' is set."
  :global t
  :group 'themer
  ;; Install from `prog-mode-hook' first, before other mode hooks fontify
  ;; (indent-bars, for one, skips the refontify a later flush asks for);
  ;; `after-change-major-mode-hook' catches modes not derived from prog-mode.
  (if themer-reader-treesit-mode
      (progn
        (add-hook 'prog-mode-hook #'themer-reader--install -90)
        (add-hook 'after-change-major-mode-hook #'themer-reader--install))
    (remove-hook 'prog-mode-hook #'themer-reader--install)
    (remove-hook 'after-change-major-mode-hook #'themer-reader--install))
  (dolist (buf (buffer-list))
    (with-current-buffer buf
      (if themer-reader-treesit-mode
          (themer-reader--install)
        (themer-reader--uninstall)))))

;;;; Commands

(defun themer-reader--buffer-form ()
  "The `themer-reader-deftheme' form in this buffer, or nil."
  (save-excursion
    (goto-char (point-min))
    (when (re-search-forward "^(themer-reader-deftheme\\_>" nil t)
      (goto-char (match-beginning 0))
      (ignore-errors (read (current-buffer))))))

(defun themer-reader--form-spec (form)
  "The spec plist of `themer-reader-deftheme' FORM, values evaluated.
The palette and palette names are kept as written."
  (let ((plist (nthcdr 3 form)) out)
    (while plist
      (let ((k (car plist)) (v (cadr plist)))
        (setq out (append out (list k (if (themer-reader--literal-p k v) v (eval v t))))
              plist (cddr plist))))
    out))

(defun themer-reader--current ()
  "(NAME . SPEC) for this buffer's reader theme, or the enabled one."
  (or (when-let* ((form (themer-reader--buffer-form)))
        (cons (nth 1 form) (themer-reader--form-spec form)))
      (cl-loop for th in custom-enabled-themes
               when (get th 'themer-reader-spec)
               return (cons th (get th 'themer-reader-spec)))
      (user-error "No reader theme in this buffer or enabled")))

(defun themer-reader--swatch (hex)
  "HEX propertized as a swatch."
  (if hex
      (propertize (format " %s " hex) 'face
                  `(:background ,hex :foreground ,(if (themer-colour-dark-p hex) "white" "black")))
    "-"))

(defun themer-reader-report (name derived)
  "Insert the conformance report for theme NAME from DERIVED."
  (let* ((conf (plist-get derived :conformance))
         (tiers (plist-get derived :tiers)))
    (insert (format "Reader theme `%s'\n\n" name))
    (insert (format "Conformance level: %s\n" (plist-get conf :level)))
    (insert (format "  normal vision: %s; with CVD SHOULDs as gating: %s; faces from build %s\n\n"
                    (plist-get conf :level-normal) (plist-get conf :level-cvd) (plist-get conf :build)))
    (insert "Tiers\n")
    (dolist (k '(:bg :fg :dim :faded :recessive :binding :popout :accent))
      (insert (format "  %-11s %s\n" (substring (symbol-name k) 1) (themer-reader--swatch (plist-get tiers k)))))
    (dolist (x (plist-get tiers :loud))
      (insert (format "  %-11s loud %s  quiet %s\n" (car x) (themer-reader--swatch (cdr x))
                      (themer-reader--swatch (alist-get (car x) (plist-get tiers :quiet))))))
    (insert "\nChecks\n")
    (dolist (c (plist-get conf :checks))
      (insert (format "  %s %-6s %-4s %s\n"
                      (if (plist-get c :ok) "ok  " (propertize "FAIL" 'face 'error))
                      (plist-get c :keyword) (plist-get c :section) (plist-get c :detail))))
    (insert "\nLevels tried\n")
    (pcase-dolist (`(,lv . ,p) (plist-get conf :levels))
      (insert (format "  %s loud %s (normal %s), recessive %s, quiet %s%s\n" lv
                      (if (plist-get p :loud-ok) "ok" "fail")
                      (if (plist-get p :loud-ok-normal) "ok" "fail")
                      (if (plist-get p :recessive-ok) "ok" "fail")
                      (if (plist-get p :quiet-ok) "ok" "fail")
                      (if (plist-get p :failures)
                          (concat ": " (string-join (plist-get p :failures) "; "))
                        ""))))))

;;;###autoload
(defun themer-reader-check ()
  "Show the conformance report for this buffer's reader theme, or the enabled one."
  (interactive)
  (pcase-let ((`(,name . ,spec) (themer-reader--current)))
    (let ((derived (themer-reader-derive spec)))
      (with-help-window "*themer-reader-check*"
        (with-current-buffer standard-output
          (themer-reader-report name derived))))))

(defun themer-reader--deftheme-source (name doc spec)
  "Source of the `themer-reader-deftheme' form for theme NAME with DOC and SPEC.
The palette has one entry per line."
  (concat (format "(themer-reader-deftheme %s\n  %S" name doc)
          (cl-loop for (k v) on spec by #'cddr
                   concat (if (eq k :palette)
                              (format "\n  :palette (%s)"
                                      (mapconcat (lambda (e) (format "%S" e)) v "\n            "))
                            (format "\n  %s %S" k v)))
          ")"))

(defun themer-reader--theme-source (name doc spec)
  "Source of the theme file for theme NAME with DOC and SPEC."
  (concat (format ";;; %s-theme.el --- %s -*- lexical-binding: t; -*-\n\n" name doc)
          ";; A reader-standard theme (research/PATTERNS.md); see `themer-reader-deftheme'.\n"
          ";; Edit it with `themer-reader-edit-theme', or edit an accent and\n"
          ";; re-evaluate (or use `themer-preview-mode'): every tier is derived again.\n\n"
          ";;; Code:\n\n"
          "(require 'themer-reader)\n\n"
          (themer-reader--deftheme-source name doc spec)
          "\n\n"
          (format ";;; %s-theme.el ends here\n" name)))

(defun themer-reader--read-base16 (file)
  "Alist (SLOT . HEX) of base16 slots in YAML FILE."
  (with-temp-buffer
    (insert-file-contents file)
    (let (out)
      (goto-char (point-min))
      (while (re-search-forward
              "^[ \t]*\\(base[0-9A-Fa-f]\\{2\\}\\)[ \t]*:[ \t]*[\"']?#?\\([0-9A-Fa-f]\\{6\\}\\)" nil t)
        (push (cons (match-string 1) (concat "#" (downcase (match-string 2)))) out))
      (nreverse out))))

;;;###autoload
(defun themer-reader-export (file &optional rules-note name spec)
  "Write the current reader theme to FILE as a standalone theme.
The faces have their colours baked in, with no dependency on themer.
When the spec has a palette, the entries the faces use are bound in a
`let' and named in the faces, so the export stays readable.
With RULES-NOTE (interactively, a prefix argument), add a comment on the
faces that need `themer-reader-treesit-mode' to appear.  NAME and SPEC
default to this buffer's reader theme, or the enabled one."
  (interactive
   (list (read-file-name "Export theme to: " nil nil nil
                         (format "%s-theme.el" (car (themer-reader--current))))
         current-prefix-arg))
  (pcase-let* ((`(,name . ,spec) (if spec (cons name spec) (themer-reader--current)))
               (derived (themer-reader-derive spec))
               (`(,bindings . ,specs) (themer-reader--export-specs
                                       (themer-reader-palette spec)
                                       (themer-reader--face-specs derived)))
               (out (intern (string-remove-suffix "-theme" (file-name-base file)))))
    (with-temp-file file
      (insert (format ";;; %s-theme.el --- Reader theme, exported from `%s' -*- lexical-binding: t; -*-\n\n"
                      out name)
              ";; Generated by `themer-reader-export'.  Conformance: "
              (plist-get (plist-get derived :conformance) :level) ".\n")
      (when rules-note
        (insert ";;\n;; The themer-reader-* faces (exits, type definitions, decorators,\n"
                ";; macros, parameters, TODO markers, commented-out code) are only\n"
                ";; applied by `themer-reader-treesit-mode' from the themer package.\n"
                ";; Without it, exits look like keywords and type definitions like\n"
                ";; type uses.\n"))
      (insert "\n;;; Code:\n\n"
              (format "(deftheme %s \"Reader theme exported from %s.\")\n\n" out name))
      (if (null bindings)
          (progn
            (insert (format "(custom-theme-set-faces\n '%s" out))
            (dolist (s specs)
              (insert (format "\n '%S" s)))
            (insert ")"))
        (insert "(let (" (mapconcat (lambda (b) (format "%S" b)) bindings "\n      ") ")\n"
                (format "  (custom-theme-set-faces\n   '%s" out))
        (dolist (s specs)
          (insert (format "\n   %S" (list '\` s))))
        (insert "))"))
      (insert "\n\n"
              (format "(provide-theme '%s)\n\n;;; %s-theme.el ends here\n" out out)))
    (message "Wrote %s" file)))

(defun themer-reader--export-specs (palette specs)
  "Face SPECS with the colours of PALETTE named.
PALETTE is an alist (NAME . HEX).  Return (BINDINGS . SPECS): BINDINGS
the `let' bindings of the entries used, in palette order, and SPECS with
each such colour replaced by (\\=, NAME).  The first entry of a colour
wins.  With no palette entry used, return (nil . SPECS)."
  (let* ((byhex (mapcar (lambda (e) (cons (themer-colour-norm (cdr e)) (car e))) palette))
         (used nil)
         (walk nil))
    (setq walk (lambda (x)
                 (cond ((and (stringp x) (themer-colour-hex-p x)
                             (assoc (themer-colour-norm x) byhex))
                        (let ((n (cdr (assoc (themer-colour-norm x) byhex))))
                          (cl-pushnew n used)
                          (list '\, n)))
                       ((consp x) (cons (funcall walk (car x)) (funcall walk (cdr x))))
                       (t x))))
    (let ((out (mapcar walk specs)))
      (if used
          (cons (cl-loop for (n . hex) in palette when (memq n used) collect (list n hex)) out)
        (cons nil specs)))))

(provide 'themer-reader)

;;; themer-reader.el ends here
