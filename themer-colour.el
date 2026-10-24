;;; themer-colour.el --- Colour maths for themer -*- lexical-binding: t; -*-

;; Author: beltsmith <me@alexgirdler.com>
;; Package-Requires: ((emacs "29.1"))

;;; Commentary:
;;
;; The colour maths behind the reader standard (research/notes/03), ported
;; from the reference implementation in research/harness/colour.py, which
;; uses coloraide.  Colours are "#rrggbb" strings throughout; per-colour
;; conversions are cached by hex.
;;
;;   - hex <-> sRGB <-> linear sRGB <-> OKLab / OKLCH, and CIELAB (D65).
;;   - APCA Lc (APCA-W3 0.0.98G-4g).
;;   - Szafir's line-model text colour difference `themer-colour-de-text'.
;;   - Gamut fitting: chroma reduction at constant OKLCH lightness and hue,
;;     by coloraide's ray-tracing method, so results match it.
;;   - Deutan / protan simulation (Machado 2009, full severity).
;;   - The tier derivations: lightness shift to an Lc target, fade to an
;;     Lc target, chroma cap.

;;; Code:

(require 'cl-lib)
(require 'subr-x)

;;;; Matrices (coloraide 8.x)

(defconst themer-colour--rgb-to-xyz
  [[0.4123907992659593 0.357584339383878 0.1804807884018343]
   [0.21263900587151024 0.715168678767756 0.07219231536073371]
   [0.01933081871559182 0.11919477979462598 0.9505321522496607]])

(defconst themer-colour--xyz-to-rgb
  [[3.240969941904523 -1.5373831775700941 -0.4986107602930035]
   [-0.9692436362808797 1.8759675015077204 0.04155505740717562]
   [0.05563007969699365 -0.20397695888897652 1.0569715142428784]])

(defconst themer-colour--xyz-to-lms
  [[0.819022437996703 0.3619062600528904 -0.1288737815209879]
   [0.03298365393238847 0.9292868615863434 0.03614466635064236]
   [0.04817718935962421 0.2642395317527308 0.6335478284694309]])

(defconst themer-colour--lms-to-xyz
  [[1.226879875845924 -0.5578149944602171 0.2813910456659647]
   [-0.04057574521480083 1.112286803280317 -0.07171105806551635]
   [-0.07637293667466008 -0.42149333240224324 1.5869240198367818]])

(defconst themer-colour--lms3-to-oklab
  [[0.21045426830931396 0.7936177747023053 -0.0040720430116192585]
   [1.9779985324311686 -2.42859224204858 0.450593709617411]
   [0.025904042465547734 0.7827717124575297 -0.8086757549230774]])

(defconst themer-colour--oklab-to-lms3
  [[1.0 0.3963377773761749 0.21580375730991364]
   [1.0 -0.10556134581565857 -0.0638541728258133]
   [1.0 -0.08948417752981186 -1.2914855480194092]])

(defconst themer-colour--machado
  '((deutan . [[0.367322 0.860646 -0.227968]
               [0.280085 0.672501 0.047413]
               [-0.011820 0.042940 0.968881]])
    (protan . [[0.152286 1.052583 -0.204868]
               [0.114503 0.786281 0.099216]
               [-0.003882 -0.048116 1.051998]]))
  "Machado 2009 matrices at severity 1.0, applied to linear sRGB.")

(defun themer-colour--mul (m v)
  "Matrix M (vector of row vectors) times the 3-list V."
  (let ((x (nth 0 v)) (y (nth 1 v)) (z (nth 2 v)))
    (mapcar (lambda (row)
              (+ (* (aref row 0) x) (* (aref row 1) y) (* (aref row 2) z)))
            m)))

(defun themer-colour--cbrt (x)
  "Real cube root of X."
  (if (< x 0) (- (expt (- x) (/ 1.0 3))) (if (= x 0) 0.0 (expt x (/ 1.0 3)))))

;;;; Caches

(defvar themer-colour--caches nil
  "All per-hex caches, so `themer-colour-clear-caches' can empty them.")

(defmacro themer-colour--defcache (name)
  "Define NAME as a hash table of per-hex results."
  `(progn
     (defvar ,name (make-hash-table :test #'equal))
     (add-to-list 'themer-colour--caches ',name)))

(themer-colour--defcache themer-colour--oklab-cache)
(themer-colour--defcache themer-colour--lab-cache)
(themer-colour--defcache themer-colour--apca-y-cache)
(themer-colour--defcache themer-colour--cvd-cache)

(defun themer-colour-clear-caches ()
  "Empty the per-colour caches."
  (dolist (c themer-colour--caches)
    (clrhash (symbol-value c))))

;;;; Conversions

(defun themer-colour-norm (hex)
  "Normalise HEX to lower-case \"#rrggbb\"."
  (let ((h (downcase (string-trim hex))))
    (unless (string-prefix-p "#" h) (setq h (concat "#" h)))
    (when (= (length h) 4)
      (setq h (apply #'string ?# (mapcan (lambda (c) (list c c)) (cdr (string-to-list h))))))
    (unless (string-match-p "\\`#[0-9a-f]\\{6\\}" h)
      (error "Not a hex colour: %S" hex))
    (substring h 0 7)))

(defun themer-colour-hex-p (x)
  "Non-nil if X is a \"#rrggbb\" string."
  (and (stringp x) (string-match-p "\\`#[0-9a-fA-F]\\{6\\}\\'" x)))

(defun themer-colour-hex-to-srgb (hex)
  "HEX as a list of sRGB channels in [0, 1]."
  (let ((h (themer-colour-norm hex)))
    (list (/ (string-to-number (substring h 1 3) 16) 255.0)
          (/ (string-to-number (substring h 3 5) 16) 255.0)
          (/ (string-to-number (substring h 5 7) 16) 255.0))))

(defun themer-colour--round-half-up (x)
  "Round X half up, as coloraide does."
  (floor (+ x 0.5)))

(defun themer-colour-srgb-to-hex (rgb)
  "The hex string for sRGB channels RGB, clamped to [0, 1]."
  (apply #'format "#%02x%02x%02x"
         (mapcar (lambda (c)
                   (themer-colour--round-half-up (* 255.0 (min 1.0 (max 0.0 c)))))
                 rgb)))

(defun themer-colour--to-linear (c)
  "Linear-light value of sRGB channel C (sign preserving)."
  (let ((a (abs c)))
    (* (if (< c 0) -1 1)
       (if (<= a 0.04045) (/ a 12.92) (expt (/ (+ a 0.055) 1.055) 2.4)))))

(defun themer-colour--from-linear (c)
  "Gamma-encoded sRGB value of linear channel C (sign preserving)."
  (let ((a (abs c)))
    (* (if (< c 0) -1 1)
       (if (> a 0.0031308) (- (* 1.055 (expt a (/ 1 2.4))) 0.055) (* 12.92 a)))))

(defun themer-colour-hex-to-linear (hex)
  "HEX as linear-light sRGB."
  (mapcar #'themer-colour--to-linear (themer-colour-hex-to-srgb hex)))

(defun themer-colour--linear-to-oklab (lin)
  "Linear sRGB LIN to OKLab."
  (themer-colour--mul
   themer-colour--lms3-to-oklab
   (mapcar #'themer-colour--cbrt
           (themer-colour--mul themer-colour--xyz-to-lms
                               (themer-colour--mul themer-colour--rgb-to-xyz lin)))))

(defun themer-colour--oklab-to-linear (lab)
  "OKLab LAB to linear sRGB (unclipped)."
  (themer-colour--mul
   themer-colour--xyz-to-rgb
   (themer-colour--mul themer-colour--lms-to-xyz
                       (mapcar (lambda (c) (* c c c))
                               (themer-colour--mul themer-colour--oklab-to-lms3 lab)))))

(defun themer-colour--lab-to-lch (lab)
  "Rectangular LAB to (L C h), h in degrees; h is 0 when achromatic."
  (pcase-let* ((`(,l ,a ,b) lab)
               (c (sqrt (+ (* a a) (* b b))))
               (h (if (< c 1e-6) 0.0 (mod (radians-to-degrees (atan b a)) 360.0))))
    (list l c h)))

(defun themer-colour--lch-to-lab (lch)
  "Polar LCH to rectangular Lab."
  (pcase-let ((`(,l ,c ,h) lch))
    (list l (* c (cos (degrees-to-radians h))) (* c (sin (degrees-to-radians h))))))

(defun themer-colour-oklab (hex)
  "OKLab coordinates of HEX."
  (with-memoization (gethash hex themer-colour--oklab-cache)
    (themer-colour--linear-to-oklab (themer-colour-hex-to-linear hex))))

(defun themer-colour-oklch (hex)
  "OKLCH coordinates (L C h) of HEX; h is 0 for achromatic colours."
  (themer-colour--lab-to-lch (themer-colour-oklab hex)))

(defconst themer-colour--d65
  (list (/ 0.3127 0.329) 1.0 (/ (- 1 0.3127 0.329) 0.329))
  "D65 white (x 0.3127, y 0.3290) as XYZ.")

(defun themer-colour-lab (hex)
  "CIELAB (D65) coordinates of HEX."
  (with-memoization (gethash hex themer-colour--lab-cache)
    (let* ((xyz (themer-colour--mul themer-colour--rgb-to-xyz
                                    (themer-colour-hex-to-linear hex)))
           (eps (/ 216.0 24389))
           (kappa (/ 24389.0 27))
           (f (lambda (v w)
                (let ((tt (/ v w)))
                  (if (> tt eps) (themer-colour--cbrt tt) (/ (+ (* kappa tt) 16) 116.0)))))
           (fx (funcall f (nth 0 xyz) (nth 0 themer-colour--d65)))
           (fy (funcall f (nth 1 xyz) (nth 1 themer-colour--d65)))
           (fz (funcall f (nth 2 xyz) (nth 2 themer-colour--d65))))
      (list (- (* 116 fy) 16) (* 500 (- fx fy)) (* 200 (- fy fz))))))

;;;; Gamut fitting (coloraide `raytrace', CSS fast path)

(defconst themer-colour--atol 1e-12)

(defun themer-colour--in-gamut-p (lin)
  "Non-nil if linear sRGB LIN lies inside the unit cube."
  (cl-every (lambda (x) (and (>= x 0.0) (<= x 1.0))) lin))

(defun themer-colour--project-onto (a b o)
  "Project the vector from O to A onto the one from O to B, clamped to it."
  (let* ((va (cl-mapcar #'- a o))
         (vb (cl-mapcar #'- b o))
         (d (apply #'+ (cl-mapcar #'* vb vb)))
         (r (/ (apply #'+ (cl-mapcar #'* va vb)) (if (= d 0) 1e-12 d))))
    (setq r (min 1.0 (max 0.0 r)))
    (cl-mapcar (lambda (v ox) (+ (* v r) ox)) vb o)))

(defun themer-colour--raytrace-box (start end)
  "Where the ray from START to END meets the unit cube, or nil (slab method)."
  (let ((tfar 1.0e+INF) (tnear -1.0e+INF) (small t) dir hit)
    (catch 'miss
      (dotimes (i 3)
        (let* ((a (nth i start)) (b (nth i end)) (d (- b a)))
          (push d dir)
          (when (and small (> (abs d) themer-colour--atol)) (setq small nil))
          (if (/= d 0)
              (let ((t1 (/ (- 0.0 a) d)) (t2 (/ (- 1.0 a) d)))
                (setq tnear (max (min t1 t2) tnear)
                      tfar (min (max t1 t2) tfar)))
            (when (or (< a 0.0) (> a 1.0)) (throw 'miss nil)))))
      (setq dir (nreverse dir))
      (when (or small (> tnear tfar) (< tfar 0)) (throw 'miss nil))
      (when (< tnear 0.0) (setq tnear tfar))
      (when (isnan (* 0 tnear)) (throw 'miss nil))
      (setq hit (cl-mapcar (lambda (s d) (+ s (* d tnear))) start dir))
      hit)))

(defun themer-colour--fit-lch (lch)
  "Linear sRGB for OKLCH LCH, chroma reduced (at fixed L and h) into gamut."
  (let* ((start (copy-sequence lch))
         (to-lin (lambda (c) (themer-colour--oklab-to-linear (themer-colour--lch-to-lab c))))
         (coords (funcall to-lin start)))
    (if (themer-colour--in-gamut-p coords)
        coords
      (let* ((anchor (themer-colour--project-onto
                      (funcall to-lin (list (nth 0 lch) 0.0 (nth 2 lch)))
                      '(1.0 1.0 1.0) '(0.0 0.0 0.0)))
             (last coords))
        (cond
         ((equal anchor '(1.0 1.0 1.0)) anchor)
         ((equal anchor '(0.0 0.0 0.0)) anchor)
         (t
          (catch 'done
            (dotimes (i 4)
              (when (> i 0)
                (let ((c (themer-colour--lab-to-lch (themer-colour--linear-to-oklab coords))))
                  (setq coords (funcall to-lin (list (nth 0 start) (nth 1 c) (nth 2 start))))))
              (let ((hit (themer-colour--raytrace-box anchor coords)))
                (unless hit
                  (setq coords last)
                  (throw 'done nil))
                (when (and (> i 0)
                           (cl-every (lambda (x) (and (< themer-colour--atol x)
                                                      (< x (+ 1.0 themer-colour--atol))))
                                     coords))
                  (setq anchor coords))
                (setq last hit coords hit))))
          (mapcar (lambda (x) (min 1.0 (max 0.0 x))) coords)))))))

(defun themer-colour--linear-to-hex (lin)
  "Hex for linear sRGB LIN, gamut-fitted in OKLCH if outside sRGB."
  (unless (themer-colour--in-gamut-p lin)
    (setq lin (themer-colour--fit-lch
               (themer-colour--lab-to-lch (themer-colour--linear-to-oklab lin)))))
  (themer-colour-srgb-to-hex (mapcar #'themer-colour--from-linear lin)))

(defun themer-colour-from-oklch (l c h)
  "Hex for OKLCH (L C H), with L clamped to [0, 1], C >= 0, gamut-fitted."
  (themer-colour-srgb-to-hex
   (mapcar #'themer-colour--from-linear
           (themer-colour--fit-lch (list (max 0.0 (min 1.0 l)) (max 0.0 c) h)))))

(defun themer-colour-from-oklab (lab)
  "Hex for OKLab LAB, gamut-fitted."
  (themer-colour--linear-to-hex (themer-colour--oklab-to-linear lab)))

(defun themer-colour-mix (a b tt)
  "OKLab mix of hex colours A and B: TT 0 gives A, 1 gives B."
  (themer-colour-from-oklab
   (cl-mapcar (lambda (x y) (+ x (* (- y x) tt)))
              (themer-colour-oklab a) (themer-colour-oklab b))))

;;;; Differences

(defun themer-colour-de-ok (a b)
  "Euclidean OKLab difference between hex colours A and B."
  (let ((d (cl-mapcar #'- (themer-colour-oklab a) (themer-colour-oklab b))))
    (sqrt (apply #'+ (cl-mapcar #'* d d)))))

(defun themer-colour-nd-line (p s)
  "Szafir 2018 Eqs 14-16 (lines): noticeable CIELAB step per axis.
P is the fraction of viewers who see the difference, S the size in degrees."
  (mapcar (lambda (ck) (/ p (- (car ck) (/ (cdr ck) s))))
          '((0.0742 . 0.0023) (0.0623 . 0.0015) (0.0425 . 0.0009))))

(defvar themer-colour--nd nil)

(defun themer-colour-de-text (a b &optional p s)
  "Szafir line-model text difference of hex colours A and B (CIELAB D65).
P defaults to 0.8, S to 0.1 degrees.  1 or more means a fraction P of
viewers can tell the two apart as text."
  (let* ((p (or p 0.8)) (s (or s 0.1))
         (nd (or (cdr (assoc (cons p s) themer-colour--nd))
                 (let ((v (themer-colour-nd-line p s)))
                   (push (cons (cons p s) v) themer-colour--nd)
                   v)))
         (la (themer-colour-lab a)) (lb (themer-colour-lab b)))
    (sqrt (+ (expt (/ (- (nth 0 la) (nth 0 lb)) (nth 0 nd)) 2)
             (expt (/ (- (nth 1 la) (nth 1 lb)) (nth 1 nd)) 2)
             (expt (/ (- (nth 2 la) (nth 2 lb)) (nth 2 nd)) 2)))))

(defun themer-colour-d1 (a b &optional level)
  "D1: A and B distinguishable as text.
LEVEL `reliable' tests p = .8; otherwise the floor, p = .5."
  (>= (themer-colour-de-text a b (if (eq level 'reliable) 0.8 0.5)) 1.0))

(defconst themer-colour--hue-bins
  '((37 . red) (75 . orange) (116 . yellow) (175 . green)
    (225 . cyan) (275 . blue) (335 . purple))
  "OKLCH hue bins (upper bound, exclusive), walked from 12 degrees.")

(defun themer-colour-hue-name (hex)
  "Basic colour name of HEX: grey below C 0.04, brown for dark orange/yellow."
  (pcase-let ((`(,l ,c ,h) (themer-colour-oklch hex)))
    (if (< c 0.04)
        'grey
      (setq h (mod h 360.0))
      (if (or (>= h 335) (< h 12))
          'pink
        (let ((name (cdr (cl-find-if (lambda (b) (< h (car b))) themer-colour--hue-bins))))
          (if (and (memq name '(orange yellow)) (< l 0.5)) 'brown (or name 'pink)))))))

(defun themer-colour-d2 (a b &optional level strict)
  "D2: A and B categorically different.
D1 at LEVEL and a different hue name, or (unless STRICT) a lightness
difference of at least 0.12."
  (and (themer-colour-d1 a b level)
       (or (not (eq (themer-colour-hue-name a) (themer-colour-hue-name b)))
           (and (not strict)
                (>= (abs (- (car (themer-colour-oklch a)) (car (themer-colour-oklch b))))
                    0.12)))))

;;;; Contrast

(defun themer-colour--apca-y (hex)
  "APCA screen luminance of HEX."
  (with-memoization (gethash hex themer-colour--apca-y-cache)
    (pcase-let ((`(,r ,g ,b) (themer-colour-hex-to-srgb hex)))
      (+ (* 0.2126729 (expt r 2.4)) (* 0.7151522 (expt g 2.4)) (* 0.0721750 (expt b 2.4))))))

(defun themer-colour-apca (text bg)
  "APCA Lc of TEXT on BG (signed: negative for light text on dark)."
  (let ((tt (themer-colour--apca-y text)) (b (themer-colour--apca-y bg)))
    (setq tt (if (> tt 0.022) tt (+ tt (expt (- 0.022 tt) 1.414)))
          b (if (> b 0.022) b (+ b (expt (- 0.022 b) 1.414))))
    (cond
     ((< (abs (- b tt)) 0.0005) 0.0)
     ((> b tt)
      (let ((s (* 1.14 (- (expt b 0.56) (expt tt 0.57)))))
        (if (< s 0.1) 0.0 (* 100 (- s 0.027)))))
     (t
      (let ((s (* 1.14 (- (expt b 0.65) (expt tt 0.62)))))
        (if (> s -0.1) 0.0 (* 100 (+ s 0.027))))))))

(defun themer-colour-alc (text bg)
  "|APCA Lc| of TEXT on BG."
  (abs (themer-colour-apca text bg)))

(defun themer-colour-lc-tier (value check &optional bold)
  "Tier of |Lc| VALUE for CHECK (L1..L4): strict, default, floor or fail.
BOLD lowers the L2 thresholds by 10."
  (pcase-let ((`(,s ,d ,f) (pcase check
                             ('L1 '(75 60 45)) ('L2 '(60 45 35))
                             ('L3 '(45 30 20)) ('L4 '(15 15 15)))))
    (when (and bold (eq check 'L2))
      (setq s (- s 10) d (- d 10) f (- f 10)))
    (cond ((>= value s) 'strict) ((>= value d) 'default) ((>= value f) 'floor) (t 'fail))))

;;;; Colour vision deficiency

(defun themer-colour-cvd (hex kind)
  "HEX as seen with full-severity KIND (`deutan' or `protan').
Machado 2009 on linear sRGB, gamut-fitted.  Other KINDs return HEX."
  (let ((m (alist-get kind themer-colour--machado)))
    (if (not m)
        hex
      (with-memoization (gethash (cons hex kind) themer-colour--cvd-cache)
        (themer-colour--linear-to-hex
         (themer-colour--mul m (themer-colour-hex-to-linear hex)))))))

;;;; Derivations

(defun themer-colour-shift-l-to-lc (src bg target &optional max-fid)
  "Smallest OKLCH lightness shift of SRC, away from BG, so |Lc| >= TARGET.
With MAX-FID, the shift is limited to ΔE_OK(result, SRC) <= MAX-FID.
Return (HEX |LC| FIDELITY)."
  (let ((cur (themer-colour-alc src bg)))
    (if (>= cur target)
        (list src cur 0.0)
      (pcase-let* ((`(,l ,c ,h) (themer-colour-oklch src))
                   (up (< (car (themer-colour-oklch bg)) 0.6))
                   (lo l) (hi (if up 1.0 0.0))
                   (end (themer-colour-from-oklch hi c h))
                   (best
                    (if (< (themer-colour-alc end bg) target)
                        end
                      (let ((a lo) (b hi))
                        (dotimes (_ 30)
                          (let ((m (/ (+ a b) 2)))
                            (if (>= (themer-colour-alc (themer-colour-from-oklch m c h) bg) target)
                                (setq b m)
                              (setq a m))))
                        (themer-colour-from-oklch b c h)))))
        (when (and max-fid (> (themer-colour-de-ok best src) max-fid))
          (let ((a lo) (b (car (themer-colour-oklch best))))
            (dotimes (_ 30)
              (let ((m (/ (+ a b) 2)))
                (if (<= (themer-colour-de-ok (themer-colour-from-oklch m c h) src) max-fid)
                    (setq a m)
                  (setq b m))))
            (setq best (themer-colour-from-oklch a c h))
            (when (> (themer-colour-de-ok best src) max-fid)
              (setq best src))))
        (list best (themer-colour-alc best bg) (themer-colour-de-ok best src))))))

(defun themer-colour-fade-to-lc (fg bg target)
  "Mix FG toward BG until |Lc| is about TARGET.  Return (HEX T)."
  (if (<= (themer-colour-alc fg bg) target)
      (list fg 0.0)
    (let ((a 0.0) (b 1.0))
      (dotimes (_ 30)
        (let ((m (/ (+ a b) 2)))
          (if (>= (themer-colour-alc (themer-colour-mix fg bg m) bg) target)
              (setq a m)
            (setq b m))))
      (list (themer-colour-mix fg bg a) a))))

(defun themer-colour-cap-chroma (hex cmax)
  "HEX with its OKLCH chroma capped at CMAX."
  (pcase-let ((`(,l ,c ,h) (themer-colour-oklch hex)))
    (if (<= c cmax) hex (themer-colour-from-oklch l cmax h))))

(defun themer-colour-dark-p (hex)
  "Non-nil if HEX is a dark colour (OKLCH L < 0.6)."
  (< (car (themer-colour-oklch hex)) 0.6))

(provide 'themer-colour)

;;; themer-colour.el ends here
