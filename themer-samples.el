;;; themer-samples.el --- Code samples showing a theme's faces -*- lexical-binding: t; -*-

;; Author: beltsmith <me@alexgirdler.com>
;; Package-Requires: ((emacs "29.1"))

;;; Commentary:
;;
;; Real buffers of code, one per language, showing a set of faces without
;; enabling a theme.  A buffer that owns samples (a theme form, say) shows
;; them with `themer-samples-show' and colours them with
;; `themer-samples-update', given an alist (FACE . ATTRIBUTES).
;;
;; Each sample file is copied into a directory of the owner's own and
;; visited, so the buffer gets the major mode your Emacs uses for the file
;; and runs your hooks (rainbow-delimiters, eglot, ...) as any file would,
;; at `treesit-font-lock-level' 4.  The faces are shown through
;; `face-remapping-alist'.  With `themer-samples-semantic-tokens', eglot is
;; connected where a server is installed.  `themer-samples-kill' kills the
;; buffers, the servers started for them, and the directory.
;;
;; The samples are the files named sample.EXT in the package's samples/
;; and in `themer-samples-directory'.

;;; Code:

(require 'cl-lib)
(require 'seq)
(require 'subr-x)

(defvar treesit-font-lock-level)
(defvar eglot-sync-connect)
(declare-function eglot "eglot")
(declare-function eglot--guess-contact "eglot")
(declare-function eglot--lookup-mode "eglot")
(declare-function eglot--managed-buffers "eglot")
(declare-function eglot-current-server "eglot")
(declare-function eglot-managed-p "eglot")
(declare-function eglot-shutdown "eglot")

(defcustom themer-samples-directory nil
  "Directory of your own samples, read as well as the package's samples/.
Each file named sample.EXT is a sample; its mode, as `auto-mode-alist'
and `major-mode-remap-alist' give it, names the language.  A file here
replaces the package's file of the same name.  nil means only the
package's samples."
  :type '(choice (const :tag "None" nil) directory)
  :group 'themer)

(defcustom themer-samples-languages t
  "The languages whose samples are shown at first.
t means all of them; otherwise a list of language symbols, named for
the sample's mode (`python', `emacs-lisp', ...).  Only the first
`themer-samples-max' are shown.  `themer-samples-set-languages' changes
the choice for the session."
  :type '(choice (const :tag "The first found" t) (repeat symbol))
  :group 'themer)

(defcustom themer-samples-semantic-tokens t
  "Non-nil: connect eglot in the sample buffers, for semantic tokens.
Only for samples whose mode has an installed server in
`eglot-server-programs', and unless your own hooks connected it.  The
servers are shut down with the samples."
  :type 'boolean
  :group 'themer)

(defvar themer-samples--library-directory
  (file-name-directory (or load-file-name buffer-file-name default-directory))
  "The directory themer-samples.el was loaded from.")

;; In the owner.  Permanent, so the owner may change major mode.
(defvar-local themer-samples-title "themer-sample"
  "In a buffer owning samples: the samples' buffer names start with this.")
(defvar-local themer-samples-setup-function nil
  "In a buffer owning samples: a function called in each new sample buffer.")
(defvar-local themer-samples--buffers nil
  "The owner's sample buffers: alist LANGUAGE -> buffer.")
(defvar-local themer-samples--dir nil
  "The directory the owner's samples are copied to.")
(defvar-local themer-samples--faces nil
  "The faces last shown in the owner's samples: alist (FACE . ATTRIBUTES).")
(dolist (v '(themer-samples-title themer-samples-setup-function themer-samples--buffers
             themer-samples--dir themer-samples--faces))
  (put v 'permanent-local t))

(defvar-local themer-samples--owner nil
  "In a sample buffer: the buffer it shows samples for.")

(defconst themer-samples--language-names
  '((typescript . "TypeScript") (emacs-lisp . "Emacs Lisp"))
  "Display names of languages that `capitalize' gets wrong.")

(defvar themer-samples--selected :unset
  "The languages whose samples are shown, for this session.
:unset until `themer-samples-set-languages': then `themer-samples-languages'.")

(defun themer-samples-language-name (lang)
  "The display name of sample language LANG."
  (or (alist-get lang themer-samples--language-names)
      (capitalize (symbol-name lang))))

(defun themer-samples--file-modes (file)
  "The language of sample FILE and its candidate modes: (LANGUAGE MODE...).
The mode is FILE's in `auto-mode-alist', after `major-mode-remap-alist';
LANGUAGE is its name less -ts-mode, -mode or -ts-mode-maybe.  The
candidates are LANGUAGE-ts-mode, LANGUAGE-mode, then the mode itself.
nil if FILE has no mode."
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

(defun themer-samples-list ()
  "The samples found: a list of (LANGUAGE (MODE...) . FILE), by name.
LANGUAGE and the modes are from `themer-samples--file-modes'; a file
with no mode is named for its extension, with no modes."
  (let (files)
    (dolist (dir (list (expand-file-name "samples/" themer-samples--library-directory)
                       themer-samples-directory))
      (when (and dir (file-directory-p dir))
        (dolist (f (directory-files dir t "\\`sample\\.[^.]+\\'"))
          (setf (alist-get (file-name-nondirectory f) files nil nil #'equal) f))))
    (sort (mapcar (lambda (e)
                    (let ((lm (or (themer-samples--file-modes (cdr e))
                                  (list (intern (file-name-extension (cdr e)))))))
                      (cons (car lm) (cons (cdr lm) (cdr e)))))
                  files)
          (lambda (a b) (string< (themer-samples-language-name (car a))
                                 (themer-samples-language-name (car b)))))))

(defconst themer-samples-max 4
  "The most samples shown at once: they fill a two-by-two grid.")

(defun themer-samples-selected-languages ()
  "The languages shown, in the order of `themer-samples-list'.
At most `themer-samples-max': the first chosen, or the first found."
  (let* ((sel (if (eq themer-samples--selected :unset)
                  themer-samples-languages
                themer-samples--selected))
         (langs (mapcar #'car (themer-samples-list)))
         (chosen (seq-take (if (eq sel t) langs
                             (cl-remove-if-not (lambda (l) (memq l langs)) sel))
                           themer-samples-max)))
    (cl-remove-if-not (lambda (l) (memq l chosen)) langs)))

(defun themer-samples--buffer-name (title lang)
  "The name of the LANG sample buffer of an owner titled TITLE."
  (format "*%s (%s)*" title (themer-samples-language-name lang)))

(define-minor-mode themer-samples-mode
  "On in sample buffers.
The buffer visits a copy of a sample and shows its owner's faces
through `face-remapping-alist'; the owner kills it."
  :lighter " Sample")

(defun themer-samples--remap (buf faces)
  "Show FACES, an alist (FACE . ATTRIBUTES), in BUF in place of the theme's.
A face with no attributes is empty here too, as in a theme."
  (with-current-buffer buf
    (pcase-dolist (`(,face . ,attrs) faces)
      (face-remap-set-base face (or attrs '(:foreground unspecified))))
    (force-window-update buf)))

(defun themer-samples--semtok-contact (mode)
  "Eglot's contact for MODE if its server is installed, else nil."
  (when-let* ((guess (cdr (ignore-errors (eglot--lookup-mode mode)))))
    (or (functionp guess)
        (not (stringp (car-safe guess)))
        (executable-find (car guess)))))

(defun themer-samples--connect (buf)
  "Connect eglot in sample BUF in the background, if it has a server.
Skipped when BUF is managed already, by the user's hooks."
  (when (and themer-samples-semantic-tokens (require 'eglot nil t))
    (with-current-buffer buf
      (ignore-errors
        (when-let* (((not (or (eglot-managed-p) (eglot-current-server))))
                    ((themer-samples--semtok-contact major-mode))
                    (contact (eglot--guess-contact))
                    (program (car-safe (nth 3 contact)))
                    ((or (not (stringp program)) (executable-find program))))
          ;; Eglot manages the buffer, and paints its tokens, once the
          ;; server has initialised.
          (let ((eglot-sync-connect nil))
            (apply #'eglot contact)))))))

(defun themer-samples-visit (lang file)
  "A sample buffer for LANG visiting a copy of FILE, owned by this buffer.
It is the owner's LANG buffer from now on."
  (let ((owner (current-buffer))
        (title themer-samples-title)
        (setup themer-samples-setup-function))
    (unless (and themer-samples--dir (file-directory-p themer-samples--dir))
      (setq themer-samples--dir (make-temp-file "themer-samples-" t)))
    (let* ((copy (expand-file-name (file-name-nondirectory file) themer-samples--dir))
           (buf (progn
                  (copy-file file copy t)
                  ;; Around the setup too: it may recompute the features.
                  (let ((treesit-font-lock-level 4))
                    (with-current-buffer (find-file-noselect copy t)
                      (when setup (funcall setup))
                      (current-buffer))))))
      (with-current-buffer buf
        (rename-buffer (themer-samples--buffer-name title lang) t)
        (setq buffer-read-only t)
        (setq themer-samples--owner owner)
        (themer-samples-mode 1))
      (when themer-samples--faces
        (themer-samples--remap buf themer-samples--faces))
      (themer-samples--connect buf)
      (setf (alist-get lang themer-samples--buffers) buf))))

(defun themer-samples--ensure ()
  "The owner's sample buffers for the selected languages, made as needed."
  (let ((samples (themer-samples-list)))
    (cl-loop for lang in (themer-samples-selected-languages)
             for file = (cddr (assq lang samples))
             for buf = (alist-get lang themer-samples--buffers)
             when file
             collect (if (buffer-live-p buf) buf
                       (themer-samples-visit lang file)))))

(defun themer-samples-update (faces)
  "Show FACES, an alist (FACE . ATTRIBUTES), in this buffer's samples."
  (setq themer-samples--faces faces)
  (pcase-dolist (`(,_ . ,buf) themer-samples--buffers)
    (when (buffer-live-p buf)
      (themer-samples--remap buf faces))))

(defun themer-samples-retitle (title)
  "Rename this buffer's samples for TITLE."
  (setq themer-samples-title title)
  (pcase-dolist (`(,lang . ,buf) themer-samples--buffers)
    (when (buffer-live-p buf)
      (with-current-buffer buf
        (rename-buffer (themer-samples--buffer-name title lang) t)))))

(defconst themer-samples--width 80
  "Columns for each sample window when the grid sits beside the owner.")

(defconst themer-samples--owner-min-width 100
  "Columns the owner keeps when the samples are split off to its right.")

(defun themer-samples--hide (bufs)
  "Delete the windows showing BUFS."
  (dolist (b bufs)
    (when (buffer-live-p b)
      (dolist (w (get-buffer-window-list b nil t))
        (ignore-errors (delete-window w))))))

(defun themer-samples--place (buf direction window &rest alist)
  "Display BUF split DIRECTION off WINDOW, with ALIST; return its window.
Each split makes a new parent, so the grid's windows only share room
with each other."
  (let ((window-combination-limit t))
    (display-buffer buf `((display-buffer-in-direction)
                          (direction . ,direction) (window . ,window) ,@alist))))

(defun themer-samples-show ()
  "Show the selected samples beside this buffer, in a two-by-two grid.
The grid splits the buffer's window: to the right if it is wide enough
for both, else below.  The samples fill it left to right, then top to
bottom.  `display-buffer-alist' takes precedence.  Return the buffers."
  (interactive)
  (let ((bufs (themer-samples--ensure))
        (win (or (get-buffer-window (current-buffer)) (selected-window)))
        wide cells grid)
    ;; Laid out afresh each time, so the grid stays whole as languages
    ;; change.  Measured once the old grid is gone and its room is back.
    (themer-samples--hide (mapcar #'cdr themer-samples--buffers))
    (setq wide (>= (window-total-width win)
                   (+ themer-samples--owner-min-width (* 2 (1+ themer-samples--width)))))
    (when-let* ((b (nth 0 bufs)))
      (push (themer-samples--place b (if wide 'right 'below) win
                                   `(window-width . ,(* 2 (1+ themer-samples--width))))
            cells))
    (when-let* ((b (nth 1 bufs)) ((window-live-p (car cells))))
      (push (themer-samples--place b 'right (car cells)) cells)
      (setq grid (and (window-live-p (car cells)) (window-parent (car cells)))))
    (cl-loop for b in (nthcdr 2 bufs)
             for above in (reverse cells)
             when (window-live-p above)
             do (themer-samples--place b 'below above))
    (when (window-valid-p grid)
      (balance-windows grid))
    bufs))

(defun themer-samples-set-languages (languages)
  "Show the samples of LANGUAGES, and lay out their windows now.
Past `themer-samples-max', the languages chosen longest ago give way."
  (let* ((old (if (consp themer-samples--selected) themer-samples--selected
                (themer-samples-selected-languages)))
         (sel (append (cl-remove-if-not (lambda (l) (memq l languages)) old)
                      (cl-remove-if (lambda (l) (memq l old)) languages))))
    (setq themer-samples--selected (last sel themer-samples-max)))
  (themer-samples-show))

(defun themer-samples-kill ()
  "Kill this buffer's samples, their servers and their directory."
  (let* ((bufs (cl-remove-if-not #'buffer-live-p (mapcar #'cdr themer-samples--buffers)))
         (servers (and (fboundp 'eglot-current-server)
                       (delete-dups (delq nil (mapcar (lambda (b) (with-current-buffer b
                                                                    (eglot-current-server)))
                                                      bufs))))))
    (dolist (s servers)
      (when (cl-every (lambda (b) (memq b bufs)) (eglot--managed-buffers s))
        (ignore-errors (eglot-shutdown s))))
    (themer-samples--hide bufs)
    (dolist (b bufs)
      (when (buffer-live-p b)
        (with-current-buffer b (set-buffer-modified-p nil))
        (kill-buffer b)))
    (setq themer-samples--buffers nil)
    (when (and themer-samples--dir (file-directory-p themer-samples--dir))
      (delete-directory themer-samples--dir t))
    (setq themer-samples--dir nil)))

(provide 'themer-samples)

;;; themer-samples.el ends here
