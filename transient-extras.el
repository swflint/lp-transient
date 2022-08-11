;;; transient-extras.el --- Extra features for transient -*- lexical-binding: t -*-
;;
;; Author: Al Haji-Ali <abdo.haji.ali@gmail.com>, Samuel W. Flint <swflint@flintfam.org>
;; URL: https://github.com/haji-ali/transient-extras.git
;; Version: 0.0.1
;; Package-Requires: ((emacs "26.1"))
;; Keywords: convenience
;;
;; This file is not part of GNU Emacs.
;;
;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.
;;
;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <http://www.gnu.org/licenses/>.
;;
;;; Commentary:
;; This package provides a number of additional transient infixes and switches.
;;
;; In particular, the following are defined:
;;
;;  - `transient-extras-file-list-or-buffer' a defined argument that
;;    can be used in a transient.  It contains either the current
;;    buffer, the name of the current file, or the names of the files
;;    currently marked in `dired'.
;;
;;  - The class `transient-extras-exclusive-switch', which allows for
;;    command line switches with defined options to be cycled through.
;;    This is similar to `transient-switches', but the `choices' slot
;;    is a list of cons cells, `(value . label)', with label used for
;;    display.  Ex:
;;      (transient-define-argument lp-transient--orientation ()
;;        :description "Print Orientation"
;;        :class 'transient-extras-exclusive-switch
;;        :key "o"
;;        :argument-format "-oorientation-requested=%s"
;;        :argument-regexp "\\(-oorientation-requested=\\(4\\|5\\|6\\)\\)"
;;        :choices '(("4" . "90°(landscape)")
;;                   ("5" . "-90°")
;;                   ("6" . "180°")))
;;
;; - The class `transient-extras-option-from-dynamic-choices', based
;;   off of `transient-option'.  This allows completion of options
;;   whose choices are determined dynamically.  It requires a
;;   `choices-function' (initialized with `:choices-function') and can
;;   optionally take a `:cachep' which determines caching behavior.
;;   On first run (and any run thereafter when `:cachep' in nil
;;   (default)), the `:choices-function' is run to populate the
;;   choices list, and `transient-infix-read' is called as normal.  Ex:
;;      (transient-define-argument transient-extras-lp--printer ()
;;        :class 'transient-extras-option-dynamic-choices
;;        :description "Printer"
;;        :key "d"
;;        :argument "-d"
;;        :choices-function (transient-extras-make-command-filter
;;                           "lpstat" "-a"
;;                           (lambda (line)
;;                             (let ((index (string-match "[[:space:]]" line)))
;;                               (if index
;;                                   (substring line nil index)
;;                                 line))))
;;        :prompt "Printer? ")
;;
;; - The function `transient-extras-filter-command-output' can be used
;;   to run a command with a set of arguments, and process and filter
;;   the output line-by-line to return a list of possible choices.
;;
;; - To simplify using `transient-extras-filter-command-output' with
;;   `transient-extras-options-from-dynamic-choices', the function
;;   `transient-extras-make-command-filter' is provided.  It takes the
;;   same arguments as `transient-extras-filter-command-output' but
;;   instead returns a closure which calls
;;   `transient-extras-filter-command-output'.


(require 'transient)
(require 'cl-lib)

;;; Code:


;;; Files Lists

(defun transient-extras--get-default-file-list-or-buffer ()
  "Return the default list of files or buffer to print.
In `dired-mode', get the marked files.  In other modes, if a
buffer has a file get the filename, otherwise return the buffer
itself."
  (if (derived-mode-p 'dired-mode)
      (dired-get-marked-files)
    (or (when-let (ff (buffer-file-name))
          (list ff))
        (current-buffer))))

(defclass transient-extras-files-or-buffer (transient-infix)
  ((key         :initform "--")
   (argument    :initform "--")
   (reader      :initform #'transient-extras-read-file)
   (always-read :initform t))
  "A transient class to read list of files.
The slot `value' is either a list of files or a single buffer.")

(cl-defmethod transient-format-value ((obj transient-extras-files-or-buffer))
  "Format OBJ's value for display and return the result."
  (let ((argument (oref obj argument)))
    (if-let ((value (oref obj value)))
        (propertize
         (if (listp value)
             ;; Should be list of files.
             (mapconcat (lambda (x)
                          (file-relative-name
                           (abbreviate-file-name (string-trim x "\"" "\""))))
                        value " ")
           ;; Should be a buffer
           (prin1-to-string value))
         'face 'transient-value)
      (propertize argument 'face 'transient-inactive-value))))

(defun transient-extras-read-file (prompt _initial-input _history)
  "PROMPT for file name.

Returns a list containing the filename.  The file must exist."
  (list (file-local-name (expand-file-name
                          (read-file-name prompt nil nil t)))))

(transient-define-argument transient-extras-file-list-or-buffer ()
  :description "Files"
  :init-value (lambda (obj)
                (setf (slot-value obj 'value)
                      (transient-extras--get-default-file-list-or-buffer)))
  :class 'transient-extras-files-or-buffer)


;;; Switches with mutual exclusion

(defclass transient-extras-exclusive-switch (transient-switches) ()
  "Class used for mutually exclusive command-line switches.
Similar to function `transient-switches' except it allows choices to
contain different values and labels.  In particular, Each element
in `choices' is a cons of (value . \"label\") and label is used
for the display.")

(cl-defmethod transient-infix-read ((obj transient-extras-exclusive-switch))
  "Cycle through the mutually exclusive switches in `choices' slot of OBJ."
  (let* ((choices (mapcar
                   (apply-partially #'format (oref obj argument-format))
                   (mapcar
                    (lambda (x)
                      ;; Return car of X if it is a cons, otherwise return X.
                      (if (consp x) (car x) x))
                    (oref obj choices)))))
    (if-let ((value (oref obj value)))
        (cadr (member value choices))
      (car choices))))

(cl-defmethod transient-format-value ((obj transient-extras-exclusive-switch))
  "Format OBJ's value for display and return the result."
  (with-slots (value argument-format choices) obj
    (mapconcat
     (lambda (choice)
       (propertize
        (if (consp choice) (cdr choice) choice)
        'face
        (if (equal (format argument-format
                           (if (consp choice) (car choice) choice))
                   value)
            'transient-value
          'transient-inactive-value)))
     choices
     (propertize "|" 'face 'transient-inactive-value))))


;; Dynamic choices

(defclass transient-extras-option-dynamic-choices (transient-option)
  ((choices-function :initarg :choices-function)
   (cache-choices-p :initarg :cachep :initform nil))
  "Class used for command line options where `choices' is filled
from a function CHOICES-FUNCTION, and caching behavior is
controlled with `cache-choices-p' (`:cachep').")

(cl-defmethod transient-infix-read :around ((obj transient-extras-option-dynamic-choices))
  (with-slots (cache-choices-p choices-function) obj
    (unless (slot-boundp obj 'choices)
      (setf (oref obj choices) (funcall choices-function)))
    (prog1
        (cl-call-next-method obj)
      (unless cache-choices-p
        (slot-makeunbound obj 'choices)))))

(defun transient-extras-filter-command-output (program arguments filter)
  "FILTER the output of PROGRAM run with ARGUMENTS, removing nils."
  (cl-remove-if #'null (mapcar filter
                               (split-string (with-temp-buffer
                                               (apply (apply-partially #'call-process
                                                                       program
                                                                       nil t nil)
                                                      arguments)
                                               (buffer-string))
                                             "\n" 'omit-nulls))))

(defun transient-extras-make-command-filter (program arguments filter)
  "Return a function to FILTER output of PROGRAM with ARGUMENTS."
  (lambda ()
    (transient-extras-filter-command-output program arguments filter)))

(provide 'transient-extras)

;;; transient-extras.el ends here
