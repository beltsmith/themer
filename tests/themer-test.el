;;; themer-test.el --- Tests for themer -*- lexical-binding: t; -*-

;;; Commentary:
;;
;; Run with:
;;
;;   emacsclient --eval '(progn (load "tests/themer-test.el" nil t)
;;                              (ert-run-tests-batch "^themer-"))'
;;
;; Expected numbers come from the reference implementation in
;; research/harness: colour.py (coloraide 8.13.1) for the colour maths, and
;; mapper.map_palette(p, "reader", "C", assign=...) for the derivations,
;; with the creator assignments of harness/assignments.yaml.

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'checkdoc)

(defconst themer-test--root
  (file-name-directory (directory-file-name
                        (file-name-directory (or load-file-name buffer-file-name))))
  "The package directory.")

(add-to-list 'load-path themer-test--root)
;; Load the sources, so a long-running session tests the current code.
(dolist (f '("themer-colour" "themer-picker" "themer-reader" "themer-preview" "themer-reader-form"))
  (load (expand-file-name (concat f ".el") themer-test--root) nil t))
(themer-colour-clear-caches)
(clrhash themer-reader--cache)
(setq themer-reader--settings-cache nil)

(defun themer-test--near (got want tol)
  "Non-nil if number GOT is within TOL of WANT."
  (<= (abs (- got want)) tol))

(defun themer-test--near-list (got want tol)
  "Non-nil if lists GOT and WANT match element-wise within TOL."
  (and (= (length got) (length want))
       (cl-every (lambda (g w) (themer-test--near g w tol)) got want)))

;;;; Colour maths (colour.py)

(ert-deftest themer-colour-apca-reference ()
  "APCA reference values from research/notes/03."
  (should (themer-test--near (themer-colour-apca "#888888" "#ffffff") 63.056 0.001))
  (should (themer-test--near (themer-colour-apca "#ffffff" "#888888") -68.541 0.001))
  (should (themer-test--near (themer-colour-apca "#000000" "#aaaaaa") 58.146 0.001))
  (should (themer-test--near (themer-colour-apca "#aaaaaa" "#000000") -56.241 0.001))
  ;; Tomorrow Night (notes/03 §8)
  (should (themer-test--near (themer-colour-apca "#c5c8c6" "#1d1f21") -70.9 0.1))
  (should (themer-test--near (themer-colour-apca "#969896" "#1d1f21") -44.4 0.1)))

(ert-deftest themer-colour-conversions ()
  "OKLCH, CIELAB D65 and hue names against coloraide."
  (pcase-dolist (`(,hex ,oklch ,lab ,name)
                 '(("#cc6666" (0.630832 0.129782 21.43699) (55.3813 40.3419 18.9186) red)
                   ("#81a2be" (0.697531 0.055095 244.291674) (65.1406 -4.5867 -18.0835) blue)
                   ("#fabd2f" (0.832487 0.159484 82.986607) (80.1383 10.036 73.7119) yellow)
                   ("#282828" (0.276848 0.0 0.0) (16.1144 0.0 0.0) grey)
                   ("#d5c4a1" (0.82549 0.050676 85.115846) (79.7274 0.5039 19.7667) yellow)
                   ("#a6e22e" (0.841413 0.204441 127.28622) (83.2822 -42.8744 74.2421) green)
                   ("#f92672" (0.641578 0.240006 7.466578) (54.8081 78.0239 12.2093) pink)))
    (should (themer-test--near-list (themer-colour-oklch hex) oklch 1e-5))
    (should (themer-test--near-list (themer-colour-lab hex) lab 1e-3))
    (should (eq (themer-colour-hue-name hex) name)))
  (should (equal (themer-colour-srgb-to-hex (themer-colour-hex-to-srgb "#12abef")) "#12abef")))

(ert-deftest themer-colour-cvd ()
  "Machado 2009 full-severity simulation, gamut-fitted as coloraide does."
  (pcase-dolist (`(,hex ,deut ,prot)
                 '(("#cc6666" "#968d64" "#7d7865") ("#81a2be" "#8f9bbd" "#97a2bf")
                   ("#fabd2f" "#e5cd37" "#d6be06") ("#a6e22e" "#e6ce42" "#edd200")
                   ("#f92672" "#9b926d" "#656973")))
    (should (equal (themer-colour-cvd hex 'deutan) deut))
    (should (equal (themer-colour-cvd hex 'protan) prot)))
  ;; notes/03: Tomorrow Night blue/purple collapse under deutan
  (should (themer-test--near (themer-colour-de-ok (themer-colour-cvd "#81a2be" 'deutan)
                                                  (themer-colour-cvd "#b294bb" 'deutan))
                             0.017 0.002)))

(ert-deftest themer-colour-differences ()
  "Szafir line model and OKLab differences."
  (pcase-let ((`(,l ,a ,b) (themer-colour-nd-line 0.5 0.1)))
    (should (themer-test--near l 9.8 0.05))
    (should (themer-test--near a 10.6 0.05))
    (should (themer-test--near b 14.9 0.05)))
  (should (themer-test--near (themer-colour-de-text "#cc6666" "#81a2be") 3.13806138 1e-6))
  (should (themer-test--near (themer-colour-de-text "#cc6666" "#81a2be" 0.5) 5.02089821 1e-6))
  (should (themer-test--near (themer-colour-de-text "#282828" "#d5c4a1" 0.8 0.05) 2.32272270 1e-6))
  (should (themer-test--near (themer-colour-de-ok "#cc6666" "#81a2be") 0.18657748 1e-6))
  (should (themer-test--near (themer-colour-de-ok "#969896" "#81a2be") 0.059 0.001))
  (should (themer-colour-d2 "#81a2be" "#b294bb"))
  (should-not (themer-colour-d2 "#ff5555" "#ff6e6e")))

(ert-deftest themer-colour-gamut-and-derivations ()
  "Gamut fitting, OKLab mixing and the tier derivations."
  (should (equal (themer-colour-from-oklch 0.7 0.25 145) "#00bf34"))
  (should (equal (themer-colour-from-oklch 0.9 0.2 30) "#ffd2ca"))
  (should (equal (themer-colour-from-oklch 0.5 0.1 250) "#32669a"))
  (should (equal (themer-colour-from-oklch 0.3 0.3 300) "#3d006f"))
  (should (equal (themer-colour-mix "#cc6666" "#81a2be" 0.3) "#bb7b81"))
  (should (equal (themer-colour-mix "#a6e22e" "#f92672" 0.5) "#e0995f"))
  (pcase-let ((`(,hex ,lc ,fid) (themer-colour-shift-l-to-lc "#cc6666" "#1d1f21" 45)))
    (should (equal hex "#e27a79"))
    (should (themer-test--near lc 45.2094 1e-3))
    (should (themer-test--near fid 0.064707 1e-5)))
  (pcase-let ((`(,hex ,lc ,fid) (themer-colour-shift-l-to-lc "#cc6666" "#1d1f21" 45 0.05)))
    (should (equal hex "#dd7575"))
    (should (themer-test--near lc 42.8212 1e-3))
    (should (<= fid 0.0501)))
  (pcase-let ((`(,hex ,tt) (themer-colour-fade-to-lc "#c5c8c6" "#1d1f21" 30)))
    (should (equal hex "#787b7b"))
    (should (themer-test--near tt 0.423933 1e-5))))

;;;; Derivation (mapper.py mode C)

(defconst themer-test--palettes
  '((gruvbox
     (:bg "#282828" :fg "#d5c4a1" :syntax "#fb4934" :callable "#b8bb26" :type "#fabd2f"
      :value "#d3869b" :meta "#8ec07c" :binding "#83a598" :popout "#fe8019"
      :error "#fb4934" :warning "#fabd2f" :added "#b8bb26")
     :level-normal R2 :level-cvd none
     :loud ((callable . "#b8bb26") (syntax . "#ff6651") (value . "#d3869b"))
     :dim "#a79b81" :faded "#857d6a" :recessive "#f29281"
     :quiet ((callable . "#b2b669") (value . "#e3b9c3")) :binding "#a7d1c1"
     :failures ((R0 "meta/syntax: deutan" "type/callable: D2, deutan, protan" "callable/syntax: deutan")
                (R1 "type/callable: D2, deutan, protan" "callable/syntax: deutan")
                (R2 "callable/syntax: deutan")))
    (monokai
     (:bg "#272822" :fg "#f8f8f2" :syntax "#f92672" :callable "#a6e22e" :type "#66d9ef"
      :value "#ae81ff" :meta "#fd971f" :binding "#a1efe4" :popout "#fd971f"
      :error "#f92672" :warning "#f4bf75" :added "#a6e22e")
     :level-normal R3 :level-cvd R3
     :loud ((callable . "#a6e22e") (syntax . "#ff4e82") (value . "#af84ff"))
     :dim "#9b9c95" :faded "#7d7e77" :recessive "#ffd4db"
     :quiet ((callable . "#e4fbc8") (value . nil)) :binding "#acfcf1"
     :failures ((R0 "meta/callable: deutan" "quiet meta" "quiet value")
                (R1 "quiet value")
                (R2 "quiet value")))
    (kanagawa
     (:bg "#1f1f28" :fg "#dcd7ba" :syntax "#957fb8" :callable "#7e9cd8" :type "#c0a36e"
      :value "#ffa066" :meta "#c34043" :binding "#6a9589" :popout "#d27e99"
      :error "#c34043" :warning "#c0a36e" :added "#76946a")
     :level-normal R1 :level-cvd none
     :loud ((type . "#c0a36e") (callable . "#7e9cd8") (syntax . "#a48ec8") (value . "#ffa066"))
     :dim "#9d998a" :faded "#7d7b72" :recessive "#caaafd"
     :quiet ((type . "#fad38b") (callable . "#c9d6f1") (value . "#fbb38a")) :binding "#b7eede"
     :failures ((R0 "meta/type: deutan" "type/value: deutan, protan" "callable/syntax: deutan, protan"
                    "L2 meta (fail)")
                (R1 "type/value: deutan, protan" "callable/syntax: deutan, protan")
                (R2 "callable/syntax: deutan, protan")))
    (zenburn
     (:bg "#383838" :fg "#dcdccc" :syntax "#e0cf9f" :callable "#93e0e3" :type "#7cb8bb"
      :value "#dca3a3" :meta "#dfaf8f" :binding "#5f7f5f" :popout "#dc8cc3"
      :error "#dca3a3" :warning "#e0cf9f" :added "#5f7f5f")
     :level-normal R2 :level-cvd none
     :loud ((callable . "#93e0e3") (syntax . "#e0cf9f") (value . "#dca3a3"))
     :dim "#a3a499" :faded "#86867e" :recessive "#dbbb5c"
     :quiet ((callable . "#a3eaec") (value . "#ffcccc")) :binding "#b6ebb6"
     :failures ((R0 "meta/syntax: deutan, protan" "meta/value: deutan, protan"
                    "type/callable: D2, deutan, protan" "type/value: deutan, protan" "syntax/value: deutan")
                (R1 "type/callable: D2, deutan, protan" "type/value: deutan, protan" "syntax/value: deutan")
                (R2 "syntax/value: deutan"))))
  "The four creator palettes (base16; bg base00, fg base05; error/added/
warning from base08/0B/0A) and the reference mapper's results.  Tier
colours are those of the build at the normal-vision level, which the faces
use.  The binding tint is mapper.apply_options's search run on that build.")

(defun themer-test--close (got want)
  "Non-nil if hex GOT is within ΔE_OK 0.02 of WANT (both nil also counts)."
  (if (or (null got) (null want))
      (equal got want)
    (<= (themer-colour-de-ok got want) 0.02)))

(defmacro themer-test--defpalette (name)
  "Define a derivation test for palette NAME of `themer-test--palettes'."
  `(ert-deftest ,(intern (format "themer-reader-derive-%s" name)) ()
     ,(format "Conformance and tiers for %s match the reference mapper." name)
     (let* ((ref (cdr (assq ',name themer-test--palettes)))
            (spec (car ref)) (ref (cdr ref))
            (d (themer-reader-derive spec))
            (conf (plist-get d :conformance))
            (tiers (plist-get d :tiers)))
       (should (eq (plist-get conf :level-normal) (plist-get ref :level-normal)))
       (should (eq (plist-get conf :level-cvd) (plist-get ref :level-cvd)))
       (pcase-dolist (`(,lv . ,fails) (plist-get ref :failures))
         (let ((mine (cl-remove-if (lambda (f) (string-prefix-p "dim" f))
                                   (plist-get (alist-get lv (plist-get conf :levels)) :failures))))
           (should (equal (sort (copy-sequence mine) #'string<)
                          (sort (copy-sequence fails) #'string<)))))
       (dolist (k '(:dim :faded :recessive :binding))
         (should (themer-test--close (plist-get tiers k) (plist-get ref k))))
       (pcase-dolist (`(,f . ,hex) (plist-get ref :loud))
         (should (themer-test--close (alist-get f (plist-get tiers :loud)) hex)))
       (pcase-dolist (`(,f . ,hex) (plist-get ref :quiet))
         (should (themer-test--close (alist-get f (plist-get tiers :quiet)) hex))))))

(themer-test--defpalette gruvbox)
(themer-test--defpalette monokai)
(themer-test--defpalette kanagawa)
(themer-test--defpalette zenburn)

(ert-deftest themer-reader-roles ()
  "Role styles follow reader.yaml, with shedding applied."
  (let* ((d (themer-reader-derive (cadr (assq 'gruvbox themer-test--palettes))))
         (roles (plist-get d :roles))
         (tiers (plist-get d :tiers))
         (fg (lambda (r) (plist-get (alist-get r roles) :foreground))))
    (should (eq (plist-get (alist-get 'keyword.exit roles) :weight) 'bold))
    (should (eq (plist-get (alist-get 'function.def roles) :weight) 'bold))
    (should (eq (plist-get (alist-get 'keyword.other roles) :weight) 'normal))
    (should (equal (funcall fg 'keyword.other) (plist-get tiers :recessive)))
    (should (equal (funcall fg 'variable.use) (plist-get tiers :fg)))
    (should (equal (funcall fg 'comment) (plist-get tiers :dim)))
    (should (equal (funcall fg 'punctuation) (plist-get tiers :faded)))
    (should (equal (funcall fg 'parameter) (plist-get tiers :binding)))
    ;; R2: types fold into the callable family; meta into syntax, loud.
    (should (equal (funcall fg 'type.use) (alist-get 'callable (plist-get tiers :quiet))))
    (should (equal (funcall fg 'macro.call) (alist-get 'syntax (plist-get tiers :loud))))
    (should (plist-get (alist-get 'mod.deprecated roles) :strike))))

(ert-deftest themer-reader-define-and-export ()
  "A theme gets the derived faces; the export has no themer dependency."
  (let ((themer-reader-enable-rules nil)
        (spec (cadr (assq 'zenburn themer-test--palettes)))
        (file (make-temp-file "themer-export-" nil "-theme.el")))
    (unwind-protect
        (progn
          (custom-declare-theme 'themer-test-scratch nil)
          (let* ((d (themer-reader-define 'themer-test-scratch spec))
                 (setting (cl-find-if (lambda (s) (eq (nth 1 s) 'font-lock-keyword-face))
                                      (get 'themer-test-scratch 'theme-settings))))
            (should setting)
            (should (equal (plist-get (cdr (car (nth 3 setting))) :foreground)
                           (plist-get (plist-get d :tiers) :recessive))))
          (cl-letf (((symbol-function 'themer-reader--current)
                     (lambda () (cons 'themer-test-scratch spec))))
            (themer-reader-export file t))
          (with-temp-buffer
            (insert-file-contents file)
            (should-not (string-search "(require 'themer" (buffer-string)))
            (should (string-search "themer-reader-treesit-mode" (buffer-string)))
            (goto-char (point-min))
            (should (condition-case nil (progn (while (read (current-buffer))) t)
                      (end-of-file t)))))
      (delete-file file)
      (put 'themer-test-scratch 'theme-settings nil)
      (setq custom-known-themes (delq 'themer-test-scratch custom-known-themes)))))

(ert-deftest themer-reader-spec-errors ()
  "Missing or malformed required keys are errors."
  (should-error (themer-reader-derive '(:bg "#000000" :fg "#ffffff")))
  (should-error (themer-reader-derive '(:bg "#000000" :fg "#ffffff" :syntax "red"
                                        :callable "#00ff00" :value "#0000ff"))))

;;;; Tree-sitter rules

(ert-deftest themer-reader-queries-compile ()
  "Every rule group compiles for each installed grammar."
  (let ((tested 0))
    (dolist (lang themer-reader--languages)
      (when (treesit-language-available-p lang)
        (pcase-dolist (`(,group . ,query) (themer-reader--queries lang))
          (cl-incf tested)
          (should (equal (list lang group nil)
                         (list lang group (themer-reader--query-ok lang query)))))))
    (should (> tested 0))))

(ert-deftest themer-reader-rust-try-is-exit ()
  "Rust `?' gets the exit face with the rules mode on."
  (skip-unless (and (treesit-language-available-p 'rust) (require 'rust-ts-mode nil t)))
  (let ((themer-reader-fade-commented-code t)
        (was themer-reader-treesit-mode))
    (unwind-protect
        (progn
          (themer-reader-treesit-mode 1)
          (with-temp-buffer
            (insert "use std::collections::HashMap;\nuse a::{b, c};\nmod m;\n"
                    "fn f() -> R {\n    // TODO: tidy\n    // let x = compute(a, b);\n"
                    "    let v = g()?;\n    Ok(v)\n}\nstruct P { x: i32 }\nconst M: i32 = i32::MAX;\n")
            (rust-ts-mode)
            (run-hooks 'after-change-major-mode-hook)
            (font-lock-ensure)
            (cl-flet ((face-at (s) (goto-char (point-min)) (search-forward s)
                               (get-text-property (match-beginning 0) 'face)))
              (should (eq (face-at "?;") 'themer-reader-exit))
              (should (eq (face-at "TODO") 'themer-reader-todo))
              (should (eq (face-at "let x") 'themer-reader-commented-code))
              (should (eq (face-at "P {") 'themer-reader-type-definition))
              (should (eq (face-at "std::") 'themer-reader-module))
              (should (eq (face-at "collections::") 'themer-reader-module))
              (should (eq (face-at "a::{") 'themer-reader-module))
              (should (eq (face-at "m;") 'themer-reader-module))
              (should (eq (face-at "HashMap") 'font-lock-type-face))
              (should-not (eq (face-at "i32::") 'themer-reader-module)))))
      (themer-reader-treesit-mode (if was 1 -1)))))

(defconst themer-test--bindings
  '((python python-ts-mode
     "X_MAX = 1\ncount = 0\na, b = 2, 3\nclass C:\n    K = 1\n    def f(self):\n        y = 2\n        LOCAL_C = 3\n"
     (("X_MAX" . c) ("count" . m) ("a," . m) ("b =" . m) ("K =" . m) ("y =" . l) ("LOCAL_C" . l)))
    (javascript js-ts-mode
     "const MAX_N = 2, base = 1;\nlet b = 3;\nvar c;\nconst {d} = o;\nexport const Q_Q = 1;\nconst h = () => { let w = 1; };\nfunction f() { const G_G = 1; let k = 2; }\n"
     (("MAX_N" . c) ("base" . m) ("b =" . m) ("c;" . m) ("d}" . m) ("Q_Q" . c) ("h =" . fn)
      ("w =" . l) ("G_G" . l) ("k =" . l)))
    (typescript typescript-ts-mode
     "const MAX_N: number = 2;\nexport const conf = {};\nlet b = 3;\nfunction f() { const g = 1; }\n"
     (("MAX_N" . c) ("conf" . m) ("b =" . m) ("g =" . l)))
    (tsx tsx-ts-mode
     "const MAX_N = 2;\nlet b = 3;\nfunction f() { const g = 1; }\n"
     (("MAX_N" . c) ("b =" . m) ("g =" . l)))
    (rust rust-ts-mode
     "const MAX: u32 = 1;\nstatic mut COUNT: u32 = 0;\nstatic NAME: &str = \"x\";\nfn f() { let y = 2; }\nimpl S { const K: u8 = 1; }\n"
     (("MAX" . c) ("COUNT" . m) ("NAME" . c) ("y =" . l) ("K:" . c)))
    (go go-ts-mode
     "package p\nconst (\n  B, C = 2, 3\n)\nvar x, y = 1, 2\nfunc f() { var l = 1; m := 2 }\n"
     (("B," . c) ("C =" . c) ("x," . m) ("y =" . m) ("l =" . l) ("m :" . l)))
    (c c-ts-mode
     "#define MAX 10\n#define SQ(x) ((x)*(x))\nstatic const int LIMIT = 5;\nint counter = 0;\nconst char *name = \"x\";\nint f(void) { const int l = 1; int m = 2; return l + m; }\n"
     (("MAX" . c) ("SQ" . macro) ("LIMIT" . c) ("counter" . m) ("name" . m) ("l =" . l) ("m =" . l)))
    (cpp c++-ts-mode
     "constexpr int N = 3;\nint v = 1;\nnamespace ns { int w = 2; }\nauto lam = [](){ int z = 1; return z; };\n"
     (("N =" . c) ("v =" . m) ("w =" . m) ("z =" . l)))
    (java java-ts-mode
     "class A { static final int MAX = 1; int f; void m() { final int l = 1; } interface I { int K = 1; } }\n"
     (("MAX" . c) ("f;" . l) ("l =" . l) ("K =" . c)))
    (lua lua-ts-mode
     "local x = 1\nlocal LIMIT <const> = 5\ng = 2\nfunction f() local y = 1; z = 3 end\n"
     (("x =" . m) ("LIMIT" . c) ("g =" . m) ("y =" . l) ("z =" . l)))
    (bash bash-ts-mode
     "X=1\nreadonly R=2\nexport E=4\nfn() { local l=1; m=2; }\n"
     (("X=" . m) ("R=" . c) ("E=" . m) ("l=" . l) ("m=" . l))))
  "Per language: (LANG MODE SOURCE ((PROBE . KIND)...)).  KIND m is a
module variable, c a constant definition, l a local (neither), fn a
function definition, macro a macro definition.")

(ert-deftest themer-reader-module-bindings ()
  "Module-level bindings and constant definitions get their faces; locals don't."
  (let ((tested 0))
    (pcase-dolist (`(,lang ,mode ,src ,probes) themer-test--bindings)
      (when (and (treesit-language-available-p lang) (fboundp mode))
        (cl-incf tested)
        (with-temp-buffer
          (insert src)
          (delay-mode-hooks (funcall mode))
          (themer-reader--install)
          (font-lock-ensure)
          (pcase-dolist (`(,probe . ,kind) probes)
            (goto-char (point-min))
            (search-forward probe)
            (let* ((face (get-text-property (match-beginning 0) 'face))
                   (faces (ensure-list face))
                   (ok (pcase kind
                         ('m (memq 'themer-reader-module-variable faces))
                         ('c (memq 'themer-reader-constant-definition faces))
                         ('fn (memq 'font-lock-function-name-face faces))
                         ('macro (memq 'themer-reader-macro-definition faces))
                         ('l (not (or (memq 'themer-reader-module-variable faces)
                                      (memq 'themer-reader-constant-definition faces)))))))
              (should (equal (list lang probe kind t) (list lang probe kind (and ok t)))))))))
    (should (> tested 0))))

(ert-deftest themer-reader-ansi-colours ()
  "Terminal colours look like their names, are readable, and brighten."
  (pcase-dolist (`(,name ,spec . ,_) themer-test--palettes)
    (let* ((tiers (plist-get (themer-reader-derive spec) :tiers))
           (bg (plist-get tiers :bg))
           (ansi (themer-reader--ansi tiers)))
      (should (equal (mapcar #'car ansi) '(red green yellow blue magenta cyan black white)))
      (pcase-dolist (`(,colour ,normal . ,bright) ansi)
        (unless (memq colour '(black white))
          (should (equal (list name colour t)
                         (list name colour (and (memq (themer-colour-hue-name normal)
                                                      (if (eq colour 'magenta) '(purple pink)
                                                        (list colour)))
                                                t))))
          (should (>= (themer-colour-alc normal bg) 35))
          (should (> (themer-colour-alc bright bg) (themer-colour-alc normal bg))))))))

(ert-deftest themer-reader-ui-faces ()
  "Magit diffs, org and outline levels follow the theme's conventions."
  (let* ((d (themer-reader-derive (cadr (assq 'gruvbox themer-test--palettes))))
         (faces (themer-reader-faces d))
         (get (lambda (f a) (plist-get (alist-get f faces) a))))
    (should (equal (funcall get 'magit-diff-added-highlight :background)
                   (funcall get 'diff-added :background)))
    (should (equal (funcall get 'magit-diff-removed-highlight :background)
                   (funcall get 'diff-removed :background)))
    (should (equal (alist-get 'org-todo faces) (alist-get 'themer-reader-todo faces)))
    (should (equal (funcall get 'org-done :foreground) (plist-get (plist-get d :tiers) :added)))
    (should (member (funcall get 'outline-2 :foreground)
                    (mapcar #'cdr (plist-get (plist-get d :tiers) :loud))))
    (should (equal (funcall get 'ansi-color-red :foreground)
                   (cadr (assq 'red (themer-reader--ansi (plist-get d :tiers))))))
    (should-not (funcall get 'marginalia-documentation :slant))
    (let ((themer-reader-italic-comments t))
      (should (eq (plist-get (alist-get 'marginalia-documentation (themer-reader-faces d)) :slant)
                  'italic)))))

(ert-deftest themer-reader-binding-faces ()
  "Module variables are bold default ink; constant definitions strong value ink."
  (let* ((d (themer-reader-derive (cadr (assq 'gruvbox themer-test--palettes))))
         (faces (themer-reader-faces d))
         (mv (alist-get 'themer-reader-module-variable faces))
         (cd (alist-get 'themer-reader-constant-definition faces)))
    (should (equal (plist-get mv :foreground) (plist-get (plist-get d :tiers) :fg)))
    (should (eq (plist-get mv :weight) 'bold))
    (should (equal (plist-get cd :foreground) (alist-get 'value (plist-get (plist-get d :tiers) :loud))))
    (should (eq (plist-get cd :weight) 'bold))
    (should (eq (plist-get (alist-get 'font-lock-variable-name-face faces) :weight) 'normal))))

;;;; Commented-out code heuristic (harness test_comment_code.py)

(defconst themer-test--code-comments
  '("// let x = compute(a, b);" "# if user.is_admin:" "#   result = fetch(url)"
    "-- local n = #items" ";; (setq fill-column 100)" "// }"
    "/* printf(\"%d\\n\", n); */" "// self.cache.insert(key, value)" "# foo.bar = 3"
    "// if (x > 0) {" "//\tl, _ := net.Listen(\"tcp\", \":8033\")"
    "// return validate(obj)" "// assertArrayEquals(new"))

(defconst themer-test--prose-comments
  '("// This function returns the number of items in the list."
    "# TODO: handle the empty case" "// Note: the lock must be held (see below)"
    "# The parser calls foo(bar) when it sees a comma and then stops"
    "// we use `retry(3)` here because the server is flaky on startup"
    "# Returns x if the cache is warm, otherwise y" "// e.g. a path like /tmp/foo"
    "/** Computes the sum of a and b. */" "#!/usr/bin/env python"
    "// ---------------------------------" "// see https://example.com/x(y);"
    "// send() detects HEAD" "// disambiguate app.use([fn])"
    "# If PAGER=bat, silently use 'less' instead to prevent"
    ";;;###autoload(autoload 'magit-log \"magit-log\" nil t)"
    ";;; mode ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;" "# shellcheck disable=SC2086"
    "// 127.65535 (tail 0xFFFF into 3 slots) -> 127.0.255.255;"))

(ert-deftest themer-reader-commented-code ()
  "The 31 cases of the harness's comment.code tests."
  (should (= 31 (+ (length themer-test--code-comments) (length themer-test--prose-comments))))
  (dolist (c themer-test--code-comments)
    (should (equal (list c t) (list c (and (themer-reader-commented-code-p c) t)))))
  (dolist (c themer-test--prose-comments)
    (should (equal (list c nil) (list c (themer-reader-commented-code-p c)))))
  ;; Multi-line: 60% of lines must look like code.
  (should (themer-reader-commented-code-p "// x = f(a);\n// y = g(b);\n// see above"))
  (should-not (themer-reader-commented-code-p
               "// x = f(a);\n// this is some prose here\n// more prose about things")))

;;;; Preview

(ert-deftest themer-preview-reader-swatches ()
  "The preview finds the theme name and paints each hex of a reader spec."
  (with-temp-buffer
    (emacs-lisp-mode)
    (insert ";; \"#123456\" in a comment\n"
            "(themer-reader-deftheme my-reader \"Doc.\"\n  :bg \"#282828\" :fg \"#d5c4a1\"\n"
            "  :syntax \"#fb4934\" :callable \"#b8bb26\" :value \"#d3869b\")\n")
    (should (eq (themer-preview--theme) 'my-reader))
    (themer-preview--paint-hexes (themer-preview--reader-bounds))
    (should (= 5 (length (cl-remove-if-not (lambda (o) (overlay-get o 'themer-preview))
                                           (overlays-in (point-min) (point-max))))))))

;;;; Form

(defun themer-test--examples ()
  "The example theme files."
  (directory-files (expand-file-name "examples" themer-test--root) t "-theme\\.el\\'"))

(ert-deftest themer-reader-form-round-trip ()
  "Parsing an example into the form model and back changes nothing."
  (should (themer-test--examples))
  (dolist (f (themer-test--examples))
    (let ((text (with-temp-buffer (insert-file-contents f) (buffer-string)))
          (m (themer-reader-form-read-file f)))
      (should (string-suffix-p (format "%s-theme.el" (plist-get m :name)) f))
      (should (equal (list f text) (list f (themer-reader-form-source m)))))))

(ert-deftest themer-reader-form-edit-and-retitle ()
  "Edits keep the header comment, renamed with the theme, and key order."
  (let* ((f (expand-file-name "examples/reader-gruvbox-theme.el" themer-test--root))
         (m (themer-reader-form-read-file f))
         (spec (themer-reader-form--merge-spec
                (plist-get m :spec)
                (append (list :removed "#cc241d") (plist-put (copy-sequence (plist-get m :spec)) :meta nil))))
         (m2 (append (list :name 'my-gruvbox :doc "Mine." :spec spec) m))
         (src (themer-reader-form-source m2))
         (back (themer-reader-form-parse src)))
    (should (string-prefix-p ";;; my-gruvbox-theme.el --- Mine. -*- lexical-binding: t; -*-" src))
    (should (string-search ";;; my-gruvbox-theme.el ends here" src))
    (should (string-search ";; A reader-standard theme" src))
    (should (eq (plist-get back :name) 'my-gruvbox))
    (should (equal (plist-get back :spec) spec))
    (should-not (plist-get spec :meta))
    (should (equal (last spec 2) '(:removed "#cc241d")))))

(ert-deftest themer-reader-form-save-loads ()
  "Saving writes a theme file that loads and defines the theme."
  (let* ((dir (make-temp-file "themer-form-" t))
         (themer-reader-enable-rules nil)
         (spec (cadr (assq 'zenburn themer-test--palettes)))
         (m (list :name 'themer-test-saved :doc "Saved by a test." :spec spec)))
    (unwind-protect
        (let* ((back (themer-reader-form-write m (expand-file-name "themer-test-saved-theme.el" dir)))
               (file (plist-get back :file)))
          (should (file-exists-p file))
          (should (equal (plist-get back :spec) spec))
          (load file nil t)
          (should (custom-theme-p 'themer-test-saved))
          (should (equal (get 'themer-test-saved 'themer-reader-spec) spec))
          (should (get 'themer-test-saved 'theme-settings))
          (should (equal (themer-reader-form-source back)
                         (with-temp-buffer (insert-file-contents file) (buffer-string)))))
      (put 'themer-test-saved 'theme-settings nil)
      (setq custom-known-themes (delq 'themer-test-saved custom-known-themes))
      (setq features (delq 'themer-test-saved-theme features))
      (delete-directory dir t))))

(ert-deftest themer-reader-form-statuses ()
  "Per-field statuses come from the conformance result."
  (let* ((st (themer-reader-form-statuses
              (themer-reader-derive (cadr (assq 'monokai themer-test--palettes)))))
         (text (lambda (k) (mapconcat #'cdr (alist-get k st) "; "))))
    (should (string-match-p "quiet tint" (funcall text :value)))
    (should (string-match-p "\\`Lc " (funcall text :fg)))
    (should (string-match-p "shed at" (funcall text :meta)))))

(ert-deftest themer-reader-form-buffer ()
  "The form re-derives when a colour changes and redraws the tiers."
  (let ((buf (generate-new-buffer " *themer-test-form*")))
    (unwind-protect
        (with-current-buffer buf
          (themer-reader-form--render
           (themer-reader-form--seed-model
            (expand-file-name "examples/reader-gruvbox-theme.el" themer-test--root)))
          (should (eq (plist-get (themer-reader-form-model) :name) 'reader-gruvbox-copy))
          (themer-reader-form-refresh)
          (let ((d1 themer-reader-form--derived))
            (should (equal (plist-get (plist-get d1 :conformance) :level) "R2"))
            (themer-reader-form--set :value "#83a598")
            (themer-reader-form-refresh)
            (should-not (eq d1 themer-reader-form--derived))
            (should (equal (plist-get (plist-get themer-reader-form--derived :spec) :value) "#83a598"))
            (should (string-search (alist-get 'value (plist-get (plist-get themer-reader-form--derived :tiers) :loud))
                                   (buffer-substring-no-properties themer-reader-form--dynamic (point-max))))
            ;; Unchanged colours don't re-derive.
            (let ((d2 themer-reader-form--derived))
              (themer-reader-form-refresh)
              (should (eq d2 themer-reader-form--derived)))
            (themer-reader-form--set :fg "zzz")
            (themer-reader-form-refresh)
            (should (string-search "Fix fg" (buffer-substring-no-properties
                                             themer-reader-form--dynamic (point-max))))))
      (kill-buffer buf))))

;;;; Palettes

(defconst themer-test--pal-spec
  '(:palette ((ink "#282828") (paper "#d5c4a1") (red "#fb4934") (green "#b8bb26")
              (purple "#d3869b") (spare "#123456"))
    :bg ink :fg paper :syntax red :callable green :value purple :error "#cc241d")
  "A small spec mixing palette names and a raw hex.")

(ert-deftest themer-reader-palette-resolve ()
  "Names resolve to their colours, hex strings stay, bad names are errors."
  (should (equal (themer-reader-resolve themer-test--pal-spec)
                 '(:bg "#282828" :fg "#d5c4a1" :syntax "#fb4934" :callable "#b8bb26"
                   :value "#d3869b" :error "#cc241d")))
  (should (equal (themer-reader-palette-users themer-test--pal-spec 'red) '(:syntax)))
  (should-not (themer-reader-palette-users themer-test--pal-spec 'spare))
  ;; Hex-only specs are unchanged.
  (let ((spec (cadr (assq 'gruvbox themer-test--palettes))))
    (should (equal (themer-reader-resolve spec) spec)))
  (let ((err (should-error (themer-reader-derive (plist-put (copy-sequence themer-test--pal-spec)
                                                            :syntax 'crimson)))))
    (should (string-match-p ":syntax refers to crimson, which is not in the palette"
                            (error-message-string err))))
  (should (string-match-p "has no :palette"
                          (error-message-string
                           (should-error (themer-reader-resolve '(:bg ink :fg "#ffffff"))))))
  (should-error (themer-reader-resolve '(:palette ((a "red")) :bg a)))
  (should-error (themer-reader-resolve '(:palette ((a "#000000") (a "#111111")) :bg a)))
  (should-error (themer-reader-resolve '(:palette (("a" "#000000")) :bg "#000000"))))

(ert-deftest themer-reader-palette-derive-cache ()
  "A palette spec derives as its resolved colours do, from the same cache entry."
  (let* ((spec (cadr (assq 'gruvbox themer-test--palettes)))
         (named (append '(:palette ((bg "#282828") (fg "#d5c4a1") (red "#fb4934")))
                        (plist-put (plist-put (plist-put (copy-sequence spec) :bg 'bg) :fg 'fg)
                                   :syntax 'red))))
    (should (eq (themer-reader-derive named) (themer-reader-derive spec)))
    (should (equal (plist-get (themer-reader-derive named) :spec) spec))))

(ert-deftest themer-reader-palette-examples-unchanged ()
  "The migrated examples resolve to the colours they had, and derive the same faces."
  (pcase-dolist (`(,name ,file) '((gruvbox "reader-gruvbox") (monokai "reader-monokai")
                                  (kanagawa "reader-kanagawa") (zenburn "reader-zenburn")))
    (let* ((m (themer-reader-form-read-file
               (expand-file-name (format "examples/%s-theme.el" file) themer-test--root)))
           (spec (plist-get m :spec))
           (old (cadr (assq name themer-test--palettes))))
      (should (= 16 (length (plist-get spec :palette))))
      (should (cl-every #'symbolp (cl-loop for (k v) on spec by #'cddr unless (eq k :palette) collect v)))
      ;; The accent is the one slot the old specs lack.
      (should (plist-get spec :accent))
      (let ((spec (cl-loop for (k v) on spec by #'cddr unless (eq k :accent) append (list k v))))
        (should (equal (list name (themer-reader-resolve spec)) (list name old)))
        (should (equal (themer-reader-faces (themer-reader-derive spec))
                       (themer-reader-faces (themer-reader-derive old))))))))

(ert-deftest themer-reader-palette-canonical-source ()
  "The writer reproduces the examples byte for byte, palette included."
  (dolist (f (themer-test--examples))
    (let ((text (with-temp-buffer (insert-file-contents f) (buffer-string)))
          (m (themer-reader-form-read-file f)))
      (should (equal (list f text) (list f (themer-reader-form-source (plist-put m :form nil)))))
      ;; Each slot back as written, the palette in order.
      (should (equal (plist-get (themer-reader-form-parse text) :spec) (plist-get m :spec))))))

(ert-deftest themer-reader-palette-deftheme-and-export ()
  "The macro takes palette names; the export names the palette in a `let'."
  (let* ((themer-reader-enable-rules nil)
         (dir (make-temp-file "themer-pal-" t))
         (src (expand-file-name "themer-test-pal-theme.el" dir))
         (out (expand-file-name "themer-test-palx-theme.el" dir)))
    (unwind-protect
        (progn
          (themer-reader-form-write (list :name 'themer-test-pal :doc "Palette test."
                                          :spec themer-test--pal-spec)
                                    src)
          (load src nil t)
          (should (equal (get 'themer-test-pal 'themer-reader-spec) themer-test--pal-spec))
          (themer-reader-export out nil 'themer-test-pal themer-test--pal-spec)
          (let* ((forms (with-temp-buffer
                          (insert-file-contents out)
                          (goto-char (point-min))
                          (let (fs) (condition-case nil (while t (push (read (current-buffer)) fs))
                                      (end-of-file (nreverse fs))))))
                 (let-form (cl-find-if (lambda (f) (eq (car-safe f) 'let)) forms))
                 (got nil))
            (should let-form)
            ;; Only the entries the faces use are bound, in palette order.
            (let ((names (mapcar #'car (cadr let-form))))
              (should (equal (cl-subseq names 0 2) '(ink paper)))
              (should-not (memq 'spare names))
              (should (equal names (cl-remove-if-not (lambda (n) (memq n names))
                                                     (mapcar #'car (plist-get themer-test--pal-spec :palette))))))
            (cl-letf (((symbol-function 'custom-theme-set-faces)
                       (lambda (_theme &rest specs) (setq got specs))))
              (eval let-form t))
            (should (equal got (themer-reader--face-specs (themer-reader-derive themer-test--pal-spec))))))
      (dolist (th '(themer-test-pal))
        (put th 'theme-settings nil)
        (setq custom-known-themes (delq th custom-known-themes)))
      (setq features (delq 'themer-test-pal-theme features))
      (delete-directory dir t))))

(ert-deftest themer-preview-reader-palette-swatches ()
  "The preview paints palette entries and the slots that name them."
  (with-temp-buffer
    (emacs-lisp-mode)
    (insert "(themer-reader-deftheme my-reader \"Doc mentions red.\"\n"
            "  :palette ((bg \"#282828\")\n            (red \"#fb4934\"))\n"
            "  :bg bg :fg \"#d5c4a1\" :syntax red :callable \"#b8bb26\" :value red)\n")
    (let ((pal (themer-preview--reader-palette (themer-preview--reader-bounds))))
      (should (equal pal '((bg . "#282828") (red . "#fb4934")))))
    (themer-preview--paint-hexes (themer-preview--reader-bounds))
    (let ((ovs (cl-remove-if-not (lambda (o) (overlay-get o 'themer-preview))
                                 (overlays-in (point-min) (point-max)))))
      ;; 4 hex strings, 2 palette names, 3 slot references; not the doc's "red".
      (should (= 9 (length ovs)))
      (goto-char (point-min))
      (search-forward ":syntax red")
      (let ((o (cl-find-if (lambda (o) (overlay-get o 'themer-preview)) (overlays-at (1- (point))))))
        (should (equal (plist-get (overlay-get o 'face) :background) "#fb4934"))))))

(defun themer-test--state ()
  "A form state from `themer-test--pal-spec'."
  (themer-reader-form-model-state (list :name 'x :doc "" :spec themer-test--pal-spec)))

(ert-deftest themer-reader-form-palette-state ()
  "Form states: values, resolution, rename, delete, add."
  (let* ((st (themer-test--state))
         (vals (themer-reader-form-state-values st)))
    (should (eq (plist-get vals :syntax) 'red))
    (should (equal (plist-get vals :error) "#cc241d"))
    (should (equal (plist-get (themer-reader-form-state-resolved st) :syntax) "#fb4934"))
    (should (equal (themer-reader-form-palette-users st "red") '(:syntax)))
    ;; Rename updates every slot naming the entry.
    (let ((r (themer-reader-form-palette-rename st "purple" "violet")))
      (should (equal (assoc "violet" (plist-get r :palette)) '("violet" "#d3869b")))
      (should-not (assoc "purple" (plist-get r :palette)))
      (should (equal (alist-get :value (plist-get r :slots)) "violet"))
      (should (equal (plist-get (themer-reader-form-state-resolved r) :value) "#d3869b")))
    (should-error (themer-reader-form-palette-rename st "purple" "red") :type 'user-error)
    (should-error (themer-reader-form-palette-rename st "purple" "1x") :type 'user-error)
    ;; Delete refuses while used, unless the slots take the hex.
    (should-error (themer-reader-form-palette-delete st "red") :type 'user-error)
    (let ((d (themer-reader-form-palette-delete st "red" t)))
      (should-not (assoc "red" (plist-get d :palette)))
      (should (equal (alist-get :syntax (plist-get d :slots)) "#fb4934")))
    (let ((d (themer-reader-form-palette-delete st "spare")))
      (should (= 5 (length (plist-get d :palette)))))
    ;; Add, and the model written from a state.
    (let* ((a (themer-reader-form-set-slot (themer-reader-form-palette-add st "teal" "#83A598")
                                           :binding "teal"))
           (m (themer-reader-form-state-model a (list :spec themer-test--pal-spec))))
      (should (equal (car (last (plist-get (plist-get m :spec) :palette))) '(teal "#83a598")))
      (should (eq (plist-get (plist-get m :spec) :binding) 'teal)))
    (should-error (themer-reader-form-palette-add st "red" "#000000") :type 'user-error)
    (should (equal (themer-reader-form-suggest-name st "#ff0000") "red2"))
    ;; A slot naming no entry, and an entry with a bad hex.
    (should (eq (plist-get (themer-reader-form-state-values
                            (themer-reader-form-set-slot st :type "nosuch"))
                           :type)
                :bad))
    (let ((b (themer-reader-form--state-put st :palette (cons '("ink" "zz") (cdr (plist-get st :palette))))))
      (should (eq (plist-get (themer-reader-form-state-resolved b) :bg) :bad))
      (should-error (themer-reader-form-state-model b (list :spec nil)) :type 'user-error))))

(ert-deftest themer-reader-form-pick-candidates ()
  "The Pick menu lists the palette entries in order, then custom and add."
  (let ((pal '((ink . "#282828") (red . "#fb4934"))))
    (should (equal (themer-reader-form-pick-candidates pal)
                   `(("ink" . ink) ("red" . red) (,themer-reader-form--custom . custom)
                     (,themer-reader-form--add . add))))
    (should (string-search "#fb4934" (funcall (themer-reader-form--pick-annotation pal) "red")))
    (cl-letf (((symbol-function 'completing-read) (lambda (&rest _) "red")))
      (should (eq (themer-reader-form-read-pick "x: " pal) 'red)))
    (cl-letf (((symbol-function 'completing-read) (lambda (&rest _) "#ABCDEF")))
      (should (equal (themer-reader-form-read-pick "x: " pal) "#abcdef")))
    (cl-letf (((symbol-function 'completing-read) (lambda (&rest _) themer-reader-form--add)))
      (should (eq (themer-reader-form-read-pick "x: " pal) 'add)))
    (cl-letf (((symbol-function 'completing-read) (lambda (&rest _) "nosuch")))
      (should-error (themer-reader-form-read-pick "x: " pal) :type 'user-error))))

(ert-deftest themer-reader-form-base16-palette ()
  "Base16 import fills the palette and points the slots at its entries."
  (let* ((slots (cl-loop for i below 16 collect (cons (format "base%02X" i)
                                                       (format "#%02x%02x%02x" (* i 16) (* i 8) (* i 4)))))
         (st (themer-reader-form-set-slot (themer-test--state) :binding "spare"))
         (new (themer-reader-form-base16-state st slots '((:bg . "base00") (:fg . "base05") (:type . nil)))))
    (should (equal (mapcar #'car (plist-get new :palette))
                   ;; Entries the other slots still name are kept.
                   (append (mapcar #'car slots) '("red" "green" "purple" "spare"))))
    (should (equal (alist-get :bg (plist-get new :slots)) "base00"))
    (should (equal (alist-get :type (plist-get new :slots)) ""))
    (should (equal (plist-get (themer-reader-form-state-resolved new) :fg) "#502814"))))

(ert-deftest themer-reader-form-new-theme-palette ()
  "A new theme with no seed starts with bg and fg palette entries."
  (cl-letf (((symbol-function 'face-background) (lambda (&rest _) "#101010"))
            ((symbol-function 'face-foreground) (lambda (&rest _) "#eeeeee")))
    (should (equal (plist-get (themer-reader-form--seed-model nil) :spec)
                   '(:palette ((bg "#101010") (fg "#eeeeee")) :bg bg :fg fg)))))

(ert-deftest themer-reader-form-palette-buffer ()
  "In the form, palette edits reach every slot naming the entry."
  (let ((buf (generate-new-buffer " *themer-test-form*"))
        (file (expand-file-name "examples/reader-gruvbox-theme.el" themer-test--root)))
    (unwind-protect
        (with-current-buffer buf
          (themer-reader-form--render (themer-reader-form-read-file file))
          (should (= 16 (length themer-reader-form--palette-rows)))
          (should (equal (themer-reader-form-source (themer-reader-form-model))
                         (with-temp-buffer (insert-file-contents file) (buffer-string))))
          (themer-reader-form-refresh)
          (let* ((row (cl-find "red" themer-reader-form--palette-rows
                               :key #'themer-reader-form--row-name :test #'equal))
                 (aqua (cl-find "aqua" themer-reader-form--palette-rows
                                :key #'themer-reader-form--row-name :test #'equal)))
            (should (string-search "syntax, error" (overlay-get (plist-get row :overlay) 'after-string)))
            (should (string-search "(unused)" (overlay-get (plist-get (car (last themer-reader-form--palette-rows))
                                                                      :overlay)
                                                           'after-string)))
            ;; A new hex for red re-derives syntax and error.
            (widget-value-set (plist-get row :hex) "#ee3322")
            (themer-reader-form-refresh)
            (let ((spec (plist-get themer-reader-form--derived :spec)))
              (should (equal (plist-get spec :syntax) "#ee3322"))
              (should (equal (plist-get spec :error) "#ee3322")))
            (should (eq (plist-get (plist-get (themer-reader-form-model) :spec) :syntax) 'red))
            ;; Typing a new name in the field renames the entry in the slots.
            (goto-char (widget-field-start (plist-get aqua :name)))
            (insert "x")
            (should (equal (themer-reader-form--value :meta) "xaqua"))
            (should (eq (plist-get (plist-get (themer-reader-form-model) :spec) :meta) 'xaqua))
            ;; A slot can name an entry by typing it.
            (themer-reader-form--set :callable "yellow")
            (themer-reader-form-refresh)
            (should (equal (plist-get (plist-get themer-reader-form--derived :spec) :callable) "#fabd2f"))
            ;; Deleting rows redraws the form; unknown names don't derive.
            (themer-reader-form--rerender (themer-reader-form-palette-delete
                                           (themer-reader-form--state) "yellow" t))
            (should (= 15 (length themer-reader-form--palette-rows)))
            (should (equal (themer-reader-form--value :callable) "#fabd2f"))
            (themer-reader-form--set :value "nosuch")
            (themer-reader-form-refresh)
            (should (string-search "Fix value" (buffer-substring-no-properties
                                                themer-reader-form--dynamic (point-max))))))
      (kill-buffer buf))))

;;;; Samples

(defmacro themer-test--with-form-context (&rest body)
  "Run BODY in a temporary buffer standing in for a form; kill its samples after."
  (declare (indent 0))
  `(with-temp-buffer
     (let ((themer-reader-form-semantic-tokens nil))
       (unwind-protect (progn ,@body)
         (themer-reader-form--kill-samples)))))

(defun themer-test--buffer-faces (buf)
  "The faces (flattened) in BUF, fontified."
  (with-current-buffer buf
    (font-lock-ensure)
    (let (faces (p (point-min)))
      (while (< p (point-max))
        (dolist (f (ensure-list (get-text-property p 'face))) (push f faces))
        (setq p (or (next-single-property-change p 'face) (point-max))))
      (delete-dups faces))))

(ert-deftest themer-reader-form-samples-fontify ()
  "Every built-in sample buffer has keyword, call and string faces; most have exits.
The buffers take the modes visiting gives, so C and Python are remapped
to their tree-sitter modes here."
  (let ((themer-reader-form-sample-directory nil)
        (major-mode-remap-alist '((c-mode . c-ts-mode) (python-mode . python-ts-mode))))
    (should (equal (mapcar #'car (themer-reader-form--samples))
                   '(c emacs-lisp go python rust typescript)))
    (themer-test--with-form-context
      (pcase-dolist (`(,lang ,_ . ,file) (themer-reader-form--samples))
        (let* ((buf (themer-reader-form--visit-sample lang file))
               (faces (themer-test--buffer-faces buf)))
          (should (buffer-local-value 'themer-reader-form-sample-mode buf))
          (should (buffer-local-value 'buffer-read-only buf))
          (should-not (equal (buffer-file-name buf) file))
          (dolist (f '(font-lock-keyword-face font-lock-string-face))
            (should (memq f faces)))
          (should (or (memq 'font-lock-function-call-face faces)
                      (memq 'font-lock-builtin-face faces)))
          (when (memq lang '(rust go c python typescript))
            (should (memq 'themer-reader-exit faces))))))))

(ert-deftest themer-reader-form-sample-remap ()
  "A sample buffer shows the derivation through `face-remapping-alist'."
  (let ((d (themer-reader-derive (cadr (assq 'gruvbox themer-test--palettes)))))
    (themer-test--with-form-context
      (let* ((file (cddr (assq 'rust (themer-reader-form--samples))))
             (buf (themer-reader-form--visit-sample 'rust file))
             (faces (themer-reader-faces d)))
        (themer-reader-form--remap buf d)
        (with-current-buffer buf
          (should (equal (alist-get 'font-lock-keyword-face face-remapping-alist)
                         (list (alist-get 'font-lock-keyword-face faces))))
          (should (equal (alist-get 'default face-remapping-alist)
                         (list (alist-get 'default faces))))
          ;; Empty in the theme: empty here, the face behind shows through.
          (should (equal (alist-get 'eglot-semantic-keyword face-remapping-alist)
                         '((:foreground unspecified)))))))))

(ert-deftest themer-reader-eglot-faces ()
  "Eglot faces are empty where tree-sitter knows better, coloured where it can't."
  (skip-unless (require 'eglot nil t))
  (let* ((d (themer-reader-derive (cadr (assq 'gruvbox themer-test--palettes))))
         (faces (themer-reader-faces d)))
    (dolist (f '(eglot-semantic-keyword eglot-semantic-comment eglot-semantic-string
                 eglot-semantic-documentation))
      (should (equal (list f nil) (list f (alist-get f faces)))))
    (should (plist-get (alist-get 'eglot-semantic-parameter faces) :foreground))
    (should (plist-get (alist-get 'eglot-semantic-macro faces) :foreground))
    (should (equal (alist-get 'eglot-semantic-namespace faces)
                   (alist-get 'themer-reader-module faces)))))

(ert-deftest themer-reader-rainbow-delimiters-faces ()
  "Rainbow delimiters are punctuation at every depth."
  (let ((faces (themer-reader-faces
                (themer-reader-derive (cadr (assq 'gruvbox themer-test--palettes))))))
    (dotimes (i 9)
      (should (equal (alist-get (intern (format "rainbow-delimiters-depth-%d-face" (1+ i))) faces)
                     (alist-get 'font-lock-bracket-face faces))))))

(ert-deftest themer-reader-drop-namespace-tokens ()
  "Namespace tokens stay on modules, come off types and attributes."
  (let ((s (concat (propertize "std" 'face '(eglot-semantic-namespace themer-reader-module)) " "
                   (propertize "fs" 'face '(eglot-semantic-namespace)) " "
                   (propertize "u32" 'face '(eglot-semantic-namespace font-lock-type-face)) " "
                   (propertize "derive" 'face '(eglot-semantic-namespace themer-reader-meta)))))
    (themer-reader--drop-namespace-tokens 0 (length s) s)
    (should (equal (mapcar (lambda (i) (get-text-property i 'face s)) '(0 4 7 11))
                   '((eglot-semantic-namespace themer-reader-module)
                     (eglot-semantic-namespace)
                     font-lock-type-face themer-reader-meta)))))

(ert-deftest themer-reader-form-semantic-tokens ()
  "The Rust sample buffer gets rust-analyzer's tokens; the server goes with the form."
  :tags '(:expensive)
  (skip-unless (and (require 'eglot nil t) (executable-find "rust-analyzer")
                    (treesit-language-available-p 'rust)))
  (let ((themer-reader-form-sample-directory nil)
        (deadline (+ (float-time) 60))
        buf server dir)
    (with-temp-buffer
      (let ((themer-reader-form-semantic-tokens t))
        (unwind-protect
            (progn
              (setq buf (themer-reader-form--visit-sample
                         'rust (cddr (assq 'rust (themer-reader-form--samples))))
                    dir themer-reader-form--sample-dir)
              (while (and (not (with-current-buffer buf
                                 (font-lock-ensure)
                                 (text-property-search-forward
                                  'face 'eglot-semantic-macro
                                  (lambda (v f) (memq v (ensure-list f))))))
                          (< (float-time) deadline))
                (accept-process-output nil 0.2)
                (with-current-buffer buf (goto-char (point-min))))
              (setq server (with-current-buffer buf (eglot-current-server)))
              (should server)
              (should (with-current-buffer buf
                        (goto-char (point-min))
                        (text-property-search-forward
                         'face 'eglot-semantic-macro
                         (lambda (v f) (memq v (ensure-list f)))))))
          (themer-reader-form--kill-samples))))
    (should-not (buffer-live-p buf))
    (should-not (jsonrpc-running-p server))
    (should-not (file-exists-p dir))))

(ert-deftest themer-reader-form-sample-directory ()
  "The user's sample.EXT files are found: they replace or add languages."
  (let* ((dir (make-temp-file "themer-samples" t))
         (themer-reader-form-sample-directory dir)
         (themer-reader-form--selected :unset)
         (themer-reader-form-sample-languages t)
         (major-mode-remap-alist nil))
    (unwind-protect
        (progn
          (dolist (f '(("sample.rs" . "fn mine() {}\n")
                       ("sample.rb" . "def hi = puts(\"hi\")\n")
                       ("sample.zzz" . "x\n")
                       ("notes.py" . "ignored\n")))
            (with-temp-file (expand-file-name (car f) dir) (insert (cdr f))))
          (let ((samples (themer-reader-form--samples)))
            (should (equal (mapcar #'car samples)
                           '(c emacs-lisp go python ruby rust typescript zzz)))
            (should (equal (cddr (assq 'rust samples)) (expand-file-name "sample.rs" dir)))
            (should (equal (cadr (assq 'ruby samples)) '(ruby-ts-mode ruby-mode)))
            (should (null (cadr (assq 'zzz samples))))
            (themer-test--with-form-context
              (let ((rust (themer-reader-form--visit-sample 'rust (cddr (assq 'rust samples))))
                    (zzz (themer-reader-form--visit-sample 'zzz (cddr (assq 'zzz samples)))))
                (should (equal (with-current-buffer rust (buffer-string)) "fn mine() {}\n"))
                (should (string-match-p "(Zzz)" (buffer-name zzz))))))
          (let ((themer-reader-form--selected '(ruby)))
            (should (equal (themer-reader-form--selected-languages) '(ruby)))))
      (delete-directory dir t))))

(ert-deftest themer-reader-form-sample-file-modes ()
  "Sample modes come from `auto-mode-alist': tree-sitter first, then classic."
  (let ((auto-mode-alist '(("\\.ts\\'" . typescript-ts-mode-maybe) ("\\.py\\'" . python-mode)
                           ("\\.el\\'" . emacs-lisp-mode) ("\\.sh\\'" . sh-mode)))
        (major-mode-remap-alist '((sh-mode . bash-ts-mode))))
    (should (equal (themer-reader-form--sample-file-modes "sample.ts")
                   '(typescript typescript-ts-mode typescript-mode)))
    (should (equal (themer-reader-form--sample-file-modes "sample.py")
                   '(python python-ts-mode python-mode)))
    (should (equal (themer-reader-form--sample-file-modes "sample.el")
                   '(emacs-lisp emacs-lisp-mode)))
    (should (equal (themer-reader-form--sample-file-modes "sample.sh")
                   '(bash bash-ts-mode)))
    (should-not (themer-reader-form--sample-file-modes "sample.zzz"))))

(ert-deftest themer-reader-form-sample-buffer ()
  "The sample buffers open with the form, follow its choices, and die with it."
  (let ((themer-reader-form--selected '(python rust))
        (themer-reader-form-semantic-tokens nil)
        (file (expand-file-name "examples/reader-gruvbox-theme.el" themer-test--root))
        form samples dir)
    (save-window-excursion
      (unwind-protect
          (progn
            (delete-other-windows)
            (setq form (themer-reader-edit-theme file))
            (with-current-buffer form (themer-reader-form-refresh))
            (setq samples (mapcar #'cdr (buffer-local-value 'themer-reader-form--sample-buffers form))
                  dir (buffer-local-value 'themer-reader-form--sample-dir form))
            (should (= 2 (length samples)))
            (should (equal (sort (mapcar #'buffer-name samples) #'string<)
                           '("*themer-reader-sample: reader-gruvbox (Python)*"
                             "*themer-reader-sample: reader-gruvbox (Rust)*")))
            (dolist (b samples)
              (should (get-buffer-window b))
              (should (eq form (buffer-local-value 'themer-reader-form--sample-owner b)))
              (should (string-prefix-p dir (buffer-file-name b)))
              (should (alist-get 'font-lock-keyword-face
                                 (buffer-local-value 'face-remapping-alist b))))
            (should (get-buffer-window form))
            ;; A re-derive changes the remap in place.
            (let ((b (car samples)))
              (with-current-buffer form
                (themer-reader-form--set :callable "#83a598")
                (themer-reader-form-refresh))
              (should (equal (plist-get (car (alist-get 'font-lock-function-call-face
                                                        (buffer-local-value 'face-remapping-alist b)))
                                        :foreground)
                             (plist-get (alist-get 'font-lock-function-call-face
                                                   (themer-reader-faces
                                                    (buffer-local-value 'themer-reader-form--derived form)))
                                        :foreground))))
            ;; Toggling a language shows or hides its buffer, without deriving.
            (with-current-buffer form
              (let ((d themer-reader-form--derived))
                (themer-reader-form-set-sample-languages '(rust))
                (should (eq d themer-reader-form--derived))))
            (should-not (get-buffer-window (alist-get 'python (buffer-local-value
                                                                'themer-reader-form--sample-buffers form))))
            (should (get-buffer-window (alist-get 'rust (buffer-local-value
                                                          'themer-reader-form--sample-buffers form))))
            ;; Closed window: Show samples brings it back.
            (let ((rust (alist-get 'rust (buffer-local-value 'themer-reader-form--sample-buffers form))))
              (delete-window (get-buffer-window rust))
              (with-current-buffer form (themer-reader-form-show-samples))
              (should (get-buffer-window rust))
              ;; A user rule in display-buffer-alist wins.
              (delete-window (get-buffer-window rust))
              (let ((display-buffer-alist '(("\\*themer-reader-sample" display-buffer-pop-up-window))))
                (with-current-buffer form (themer-reader-form-show-samples)))
              (should (get-buffer-window rust)))
            ;; The samples, and their directory, die with the form.
            (setq samples (mapcar #'cdr (buffer-local-value 'themer-reader-form--sample-buffers form)))
            (kill-buffer form)
            (should-not (cl-some #'buffer-live-p samples))
            (should-not (file-exists-p dir)))
        (when (buffer-live-p form) (kill-buffer form))
        (mapc (lambda (b) (when (buffer-live-p b) (kill-buffer b))) samples)))))

;;;; UI accent

(defconst themer-test--accent-spec
  '(:palette ((ink "#282828") (paper "#d5c4a1") (red "#fb4934") (green "#b8bb26")
              (purple "#d3869b") (pink "#ff00ff"))
    :bg ink :fg paper :syntax red :callable green :value purple :popout "#fe8019")
  "A spec for the accent tests.")

(defun themer-test--face-attr (derived face attr)
  "ATTR of FACE in the faces of DERIVED."
  (plist-get (alist-get face (themer-reader-faces derived)) attr))

(ert-deftest themer-reader-accent-default ()
  "The accent is :accent, else :popout, else the callable loud colour."
  (let* ((spec themer-test--accent-spec)
         (acc (lambda (s) (plist-get (plist-get (themer-reader-derive s) :tiers) :accent)))
         (no-popout (cl-loop for (k v) on spec by #'cddr unless (eq k :popout) append (list k v))))
    (should (equal (funcall acc spec) "#fe8019"))
    (should (equal (funcall acc (append spec '(:accent pink))) "#ff00ff"))
    (should (equal (funcall acc (append spec '(:accent "#00ffff"))) "#00ffff"))
    (should (equal (funcall acc no-popout)
                   (alist-get 'callable (plist-get (plist-get (themer-reader-derive no-popout) :tiers)
                                                   :loud))))
    (should-error (themer-reader-derive (append spec '(:accent nosuch))))
    (should-error (themer-reader-derive (append spec '(:accent "red"))))
    ;; A palette name and its hex are the same theme.
    (should (eq (themer-reader-derive (append spec '(:accent pink)))
                (themer-reader-derive (themer-reader-resolve (append spec '(:accent pink))))))))

(ert-deftest themer-reader-accent-faces ()
  "The accent colours the chrome faces and no syntax face."
  (let* ((spec (append themer-test--accent-spec '(:accent pink)))
         (d (themer-reader-derive spec))
         (faces (themer-reader-faces d))
         (acc "#ff00ff"))
    (should (equal (themer-test--face-attr d 'cursor :background) acc))
    (should (equal (themer-test--face-attr d 'isearch :background) acc))
    (should (equal (themer-test--face-attr d 'isearch :foreground) "#282828"))
    (should (eq (themer-test--face-attr d 'isearch :weight) 'bold))
    (dolist (f '(minibuffer-prompt line-number-current-line help-key-binding
                 mode-line-buffer-id eglot-mode-line show-paren-match
                 completions-common-part marginalia-key consult-highlight-match
                 embark-keybinding diff-hunk-header magit-section-heading
                 magit-diff-hunk-heading-highlight org-document-title org-checkbox
                 org-agenda-structure org-agenda-date-today which-key-key-face
                 dired-header eshell-prompt org-level-1 outline-1
                 orderless-match-face-0))
      (should (equal (list f (themer-test--face-attr d f :foreground)) (list f acc))))
    (should (equal (plist-get (themer-test--face-attr d 'mode-line-highlight :box) :color) acc))
    (should (equal (themer-test--face-attr d 'doom-modeline-bar :background) acc))
    (should (eq (themer-test--face-attr d 'minibuffer-prompt :weight) 'bold))
    (should (equal (themer-test--face-attr d 'org-document-title :height) 1.3))
    ;; Never on syntax.
    (pcase-dolist (`(,face . ,attrs) faces)
      (when (string-match-p "\\`\\(?:font-lock-\\|themer-reader-\\|eglot-semantic-\\)"
                            (symbol-name face))
        (should-not (member acc (list face (plist-get attrs :foreground)
                                      (plist-get attrs :background))))))))

(ert-deftest themer-reader-accent-conformance ()
  "The accent has a legibility line, and the form gives it a status."
  (let* ((ok (themer-reader-derive (append themer-test--accent-spec '(:accent "#fabd2f"))))
         (bad (themer-reader-derive (append themer-test--accent-spec '(:accent "#504945"))))
         (check (lambda (d id)
                  (seq-find (lambda (c) (eq (plist-get c :id) id))
                            (plist-get (plist-get d :conformance) :checks)))))
    (dolist (id '(accent-lc accent-isearch))
      (should (plist-get (funcall check ok id) :ok))
      (should (eq (plist-get (funcall check ok id) :keyword) 'SHOULD))
      (should-not (plist-get (funcall check bad id) :ok)))
    (should (string-search "Lc" (plist-get (funcall check ok 'accent-lc) :detail)))
    (should (equal (plist-get (plist-get ok :tiers) :accent) "#fabd2f"))
    (let ((st (themer-reader-form-statuses bad)))
      (should (string-match-p "below 60" (mapconcat #'cdr (alist-get :accent st) "; "))))
    (let ((st (themer-reader-form-statuses ok)))
      (should (string-match-p "\\`Lc " (mapconcat #'cdr (alist-get :accent st) "; "))))))

(ert-deftest themer-reader-accent-form-and-export ()
  "The accent round-trips through the form model, the writer and the export."
  (let* ((themer-reader-enable-rules nil)
         (spec (append themer-test--accent-spec '(:accent pink)))
         (m (list :name 'themer-test-accent :doc "Accent." :spec spec))
         (back (themer-reader-form-parse (themer-reader-form-source m)))
         (file (make-temp-file "themer-accent-" nil "-theme.el")))
    (should (equal (plist-get back :spec) spec))
    (should (eq (plist-get (themer-reader-form-state-values (themer-reader-form-model-state back)) :accent)
                'pink))
    (should (equal (plist-get (themer-reader-form-state-resolved (themer-reader-form-model-state back))
                              :accent)
                   "#ff00ff"))
    (should (memq :accent (themer-reader-form--keys)))
    ;; The field survives a form edit, in the spec's key order.
    (let* ((state (themer-reader-form-set-slot (themer-reader-form-model-state back) :accent "#00ffff"))
           (m2 (themer-reader-form-state-model state back)))
      (should (equal (plist-get (plist-get m2 :spec) :accent) "#00ffff")))
    (unwind-protect
        (progn
          (themer-reader-export file nil 'themer-test-accent spec)
          (with-temp-buffer
            (insert-file-contents file)
            (should (string-search ",pink" (buffer-string)))
            (should (string-search "(pink \"#ff00ff\")" (buffer-string)))))
      (delete-file file))))

;;;; Finding themes

(defmacro themer-test--with-clean-load-path (&rest body)
  "Run BODY with `custom-theme-load-path' and the path options restored after."
  (declare (indent 0))
  `(let ((old-dir (default-toplevel-value 'themer-reader-theme-directory))
         (old-inc (default-toplevel-value 'themer-reader-include-examples))
         (custom-theme-load-path nil))
     (unwind-protect (progn ,@body)
       (set-default 'themer-reader-theme-directory old-dir)
       (set-default 'themer-reader-include-examples old-inc))))

(ert-deftest themer-reader-theme-load-path ()
  "The theme and examples directories are on `custom-theme-load-path'."
  (let ((dir (file-name-as-directory (expand-file-name "themer-test-no-such-dir/"
                                                       temporary-file-directory)))
        (examples (file-name-as-directory (expand-file-name "examples" themer-test--root))))
    (themer-test--with-clean-load-path
      ;; The setter adds the directory, without creating it, and only once.
      (funcall (get 'themer-reader-theme-directory 'custom-set) 'themer-reader-theme-directory dir)
      (funcall (get 'themer-reader-theme-directory 'custom-set) 'themer-reader-theme-directory dir)
      (should (= 1 (cl-count dir custom-theme-load-path :test #'equal)))
      (should-not (file-exists-p dir))
      ;; The examples directory comes from the library's location.
      (funcall (get 'themer-reader-include-examples 'custom-set) 'themer-reader-include-examples t)
      (should (member examples custom-theme-load-path))
      (should (member "reader-gruvbox" (mapcar #'symbol-name (custom-available-themes))))
      (funcall (get 'themer-reader-include-examples 'custom-set) 'themer-reader-include-examples nil)
      (should-not (member examples custom-theme-load-path))
      (should-not (member "reader-gruvbox" (mapcar #'symbol-name (custom-available-themes))))
      (should (member dir custom-theme-load-path)))))

(ert-deftest themer-reader-setup-theme-load-path ()
  "The setup function puts both directories on the path, once."
  (let ((dir (file-name-as-directory (expand-file-name "themer-test-no-such-dir/"
                                                       temporary-file-directory)))
        (examples (file-name-as-directory (expand-file-name "examples" themer-test--root))))
    (themer-test--with-clean-load-path
      (set-default 'themer-reader-theme-directory dir)
      (set-default 'themer-reader-include-examples t)
      (should (equal (themer-reader-setup-theme-load-path) (list dir examples)))
      (themer-reader-setup-theme-load-path)
      (should (equal custom-theme-load-path (list dir examples)))
      (setq custom-theme-load-path nil)
      (set-default 'themer-reader-include-examples nil)
      (should (equal (themer-reader-setup-theme-load-path) (list dir)))
      (should (equal custom-theme-load-path (list dir))))))

(ert-deftest themer-reader-example-loads-by-name ()
  "`load-theme' finds an example by name, with the examples on the path."
  (let ((themer-reader-enable-rules nil)
        (known custom-known-themes)
        (enabled custom-enabled-themes))
    (themer-test--with-clean-load-path
      (funcall (get 'themer-reader-include-examples 'custom-set) 'themer-reader-include-examples t)
      (unwind-protect
          (progn
            (should (load-theme 'reader-gruvbox t))
            (should (memq 'reader-gruvbox custom-enabled-themes))
            (should (get 'reader-gruvbox 'themer-reader-spec)))
        (disable-theme 'reader-gruvbox)
        (put 'reader-gruvbox 'theme-settings nil)
        (setq custom-known-themes known
              custom-enabled-themes enabled)
        (setq features (delq 'reader-gruvbox-theme features))))))

(ert-deftest themer-reader-form-save-adds-directory ()
  "A theme saved to any directory becomes loadable in the session."
  (let* ((dir (file-name-as-directory (make-temp-file "themer-save-" t)))
         (buf (generate-new-buffer " *themer-test-save*")))
    (unwind-protect
        (themer-test--with-clean-load-path
          (with-current-buffer buf
            (themer-reader-form--render
             (themer-reader-form--seed-model
              (expand-file-name "examples/reader-gruvbox-theme.el" themer-test--root)))
            (let ((file (themer-reader-form-save (expand-file-name "themer-test-elsewhere-theme.el" dir))))
              (should (file-exists-p file))
              (should (member dir custom-theme-load-path))
              (themer-reader-form-save file)
              (should (= 1 (cl-count dir custom-theme-load-path :test #'equal))))))
      (kill-buffer buf)
      (delete-directory dir t))))

;;;; Picker

(ert-deftest themer-picker-adjust-in-place ()
  "Steps rewrite the hex in place; revert restores it; accept is one undo step."
  (with-temp-buffer
    (buffer-enable-undo)
    (insert "(fg \"#CC6666\")")
    (undo-boundary)
    (goto-char 8)
    (unwind-protect
        (progn
          (themer-picker-adjust)
          (themer-picker-lighter 3)
          (let ((hex (buffer-substring 6 13)))
            (should (equal hex (upcase (themer-colour-from-oklch (+ 0.630832 0.03) 0.129782 21.43699))))
            (should (equal hex (upcase hex))))
          (themer-picker-hue-up 180)
          (themer-picker-revert)
          (should (equal (buffer-string) "(fg \"#CC6666\")"))
          (should-not (overlays-in (point-min) (point-max)))
          ;; Through grey and back keeps the hue.
          (themer-picker-adjust)
          (themer-picker-less-chroma 100)
          (should (equal (buffer-substring 6 13) (upcase (themer-colour-from-oklch 0.630832 0.0 0))))
          (themer-picker-more-chroma 100)
          (themer-picker-darker 1)
          (themer-picker-accept)
          (let ((done (buffer-string)))
            (should-not (equal done "(fg \"#CC6666\")"))
            (primitive-undo 1 buffer-undo-list)
            (should (equal (buffer-string) "(fg \"#CC6666\")"))))
      (themer-picker-revert))))

(ert-deftest themer-picker-bounds ()
  "The hex at point or in the region, short forms included; nil elsewhere."
  (with-temp-buffer
    (insert "a #abc b #12ab34x c")
    (goto-char 4)
    (should (equal (themer-picker--bounds) '(3 . 7)))
    (goto-char 7)
    (should (equal (themer-picker--bounds) '(3 . 7)))
    (goto-char 12)
    (should-not (themer-picker--bounds))
    (goto-char 1)
    (should-not (themer-picker--bounds))
    (should-error (themer-picker-adjust) :type 'user-error)))

(ert-deftest themer-picker-widget-field ()
  "Adjusting inside a widget field keeps the field and notifies it."
  (with-temp-buffer
    (let* ((n 0)
           (w (widget-create 'editable-field :size 8 :format "%v" :value "#cc6666"
                             :notify (lambda (&rest _) (cl-incf n)))))
      (widget-insert "\n")
      (use-local-map widget-keymap)
      (widget-setup)
      (goto-char (1+ (widget-field-start w)))
      (unwind-protect
          (progn
            (themer-picker-adjust)
            (themer-picker-darker 5)
            (themer-picker-accept)
            (should (equal (string-trim (widget-value w))
                           (themer-colour-from-oklch (- 0.630832 0.05) 0.129782 21.43699)))
            (should (> n 0)))
        (themer-picker-revert)))))

;;;; Package hygiene

(defconst themer-test--files
  '("themer.el" "themer-colour.el" "themer-reader.el" "themer-preview.el" "themer-reader-form.el"
    "themer-picker.el")
  "Files held to the no-warnings and checkdoc rules.")

(ert-deftest themer-byte-compile-clean ()
  "The files byte-compile without warnings."
  (let ((dir (make-temp-file "themer-elc-" t))
        (load-path (cons themer-test--root load-path)))
    (unwind-protect
        (dolist (f themer-test--files)
          (let ((byte-compile-dest-file-function
                 (lambda (src) (expand-file-name (concat (file-name-nondirectory src) "c") dir)))
                (byte-compile-error-on-warn t))
            (should (equal (list f t)
                           (list f (byte-compile-file (expand-file-name f themer-test--root)))))))
      (delete-directory dir t))))

(ert-deftest themer-checkdoc-clean ()
  "checkdoc reports nothing."
  (dolist (f themer-test--files)
    (let ((warnings nil))
      (cl-letf (((symbol-function 'display-warning)
                 (lambda (_type msg &rest _) (push msg warnings))))
        (let* ((file (expand-file-name f themer-test--root))
               (visited (get-file-buffer file)))
          (unwind-protect
              (let ((checkdoc-autofix-flag 'never))
                (checkdoc-file file))
            (unless visited
              (when-let* ((buf (get-file-buffer file))) (kill-buffer buf))))))
      (should (equal (list f nil) (list f warnings))))))

(ert-deftest themer-reader-form-read-theme-file-empty ()
  "An empty answer means no seed, not the current directory."
  (cl-letf (((symbol-function 'completing-read) (lambda (&rest _) "")))
    (should (null (themer-reader-form--read-theme-file "Seed: "))))
  (cl-letf (((symbol-function 'completing-read)
             (lambda (&rest _) default-directory)))
    (should-error (themer-reader-form--read-theme-file "Seed: ") :type 'user-error)))

(provide 'themer-test)

;;; themer-test.el ends here
