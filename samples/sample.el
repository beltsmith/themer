;;; sample.el --- Config loading  -*- lexical-binding: t; -*-

(require 'cl-lib)

(defconst sample-max-retries 3 "Attempts before giving up.")
(defvar sample-cache (make-hash-table :test 'equal))

(defmacro sample-quietly (&rest body)
  "Run BODY without messages."
  `(let ((inhibit-message t)) ,@body))

;; TODO: handle timeouts
;; (message "debug")
(defun sample-load (path &optional retries)
  "Read PATH, trying RETRIES times."
  (let ((tries (or retries sample-max-retries))
        (found nil))
    (cl-loop for i from 1 to tries
             when (file-readable-p path)
             do (setq found (with-temp-buffer
                              (insert-file-contents path)
                              (message "read %s\n" path)
                              (buffer-string)))
             and return t)
    (puthash path found sample-cache)
    (unless found (error "No config at %s" path))
    (if (> tries 1) t nil)))
