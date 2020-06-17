;;; orgmark.el --- OrgMark      -*- lexical-binding: t; -*-

;; Author: Yuan Fu <casouri@gmail.com>

;;; This file is NOT part of GNU Emacs

;;; Commentary:
;;

;;; Code:
;;

(require 'cl-lib)
(require 'pcase)

;;; Backstage

(cl-defstruct orgmark-job
  type
  marker
  process
  file)

(defvar orgmark-path "orgmark"
  "Path to orgmark binary.")

(defvar orgmark--job nil
  "Last command.")

(defvar orgmark--buffer " *orgmark*"
  "Buffer for orgmark process.")

(defun orgmark--file-to-image (path)
  "Translate file PATH to image path."
  (concat (string-remove-suffix "pkdrawing" path) "png"))

(defun orgmark--file-to-pkdrawing (path)
  "Translate file PATH to pkdrawing path."
  (concat (string-remove-suffix "png" path) "pkdrawing"))

(defun orgmark--insert-image (path)
  "Copy image and drawing at PATH to current directory."
  (insert (format "[[%s]]" path)))

(defun orgmark--file-at-point ()
  "Return the path of the file at point, if any."
  (string-remove-prefix
   "file:"
   (plist-get (plist-get (text-properties-at (point))
                         'htmlize-link) :uri)))

(defun orgmark--sentinal (proc _)
  "Do stuff when orgmark process PROC quits."
  (when (and (eq proc (orgmark-job-process orgmark--job))
             (memq (process-status proc) '(exit signal)))
    (message "Orgmark process exited")
    (save-excursion
      (goto-char (orgmark-job-marker orgmark--job))
      (pcase (orgmark-job-type orgmark--job)
        ('edit nil)
        ('insert
         (orgmark--insert-image (orgmark--file-to-image
                                 (orgmark-job-file orgmark--job)))))
      (org-display-inline-images nil t))
    (setq orgmark--job nil)))

(defun orgmark--edit-file (path type)
  "Edit file at PATH."
  (if orgmark--job
      (user-error "Last job didn’t finish")
    (setq orgmark--job
          (make-orgmark-job
           :marker (point-marker)
           :process
           (pcase type
             ('insert (start-process "orgmark" orgmark--buffer orgmark-path "-n" path))
             ('edit (start-process "orgmark" orgmark--buffer orgmark-path path)))
           :file path
           :type type))
    (set-process-sentinel (orgmark-job-process orgmark--job)
                          #'orgmark--sentinal)))

;;; Userland

(defun orgmark-insert ()
  "Insert a drawing at point of SIZE."
  (interactive)
  (let ((file (expand-file-name
               (format "%s.pkdrawing"
                       (format-time-string "%Y%m%d%H%M%S")))))
    (orgmark--edit-file file 'insert)))

(defun orgmark-edit ()
  "Edit image at point."
  (interactive)
  (if-let ((path (orgmark--file-at-point)))
      (orgmark--edit-file (orgmark--file-to-pkdrawing path) 'edit)
    (user-error "No file at point")))

(defun orgmark-abort ()
  "Abort this edit."
  (interactive)
  (delete-process (orgmark-job-process orgmark--job))
  (setq orgmark--job nil))

(provide 'orgmark)

;;; orgmark.el ends here
