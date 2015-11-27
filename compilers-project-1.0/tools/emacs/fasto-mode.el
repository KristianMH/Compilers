;;; fasto-mode.el --- major mode for editing FASTO source files

;; Copyright (C) DIKU, University of Copenhagen
;;   Based on futhark-mode.el <https://github.com/HIPERFIT/futhark>,
;;   written by Troels Henriksen <athas@sigkill.dk> and
;;   Niels G. W. Serup <ngws@metanohi.name> in 2013-2014.
;;
;;   fasto-mode.el written by Niels G. W. Serup in 2014-2015.
;;
;; Licensed under BSD3.

;; This mode provides the following features for FASTO source files:
;;   + syntax highlighting
;;   + automatic indentation
;;   + experimental, interactive program interpretation
;;
;; To load fasto-mode automatically on Emacs startup, put this file in
;; your load path and require the mode, e.g. something like this:
;;
;;   (add-to-list 'load-path "~/.emacs.d/fasto")
;;   (require 'fasto-mode)
;;
;; In this case, you have to create the directory "~/.emacs.d/fasto" and
;; store this file in that directory.
;;
;; This will also tell your Emacs that .fo files are to be handled by
;; fasto-mode.
;;
;; Local keybindings:
;;
;;   C-c C-l: `fasto-interpret'.  Run the FASTO interpreter ("fasto
;;            -i") on the current file and show the output in another
;;            buffer.  fasto-mode will guess the location of the
;;            "fasto" binary unless you globally define `fasto-binary'.
;;
;; Define local keybindings in `fasto-mode-map`, and add startup
;; functions to `fasto-mode-hook`.
;;
;; Report bugs to Niels.


;;; Basics

(require 'cl)

;;;###autoload
(add-to-list 'auto-mode-alist '("\\.fo\\'" . fasto-mode))

(defvar fasto-mode-hook nil
  "Hook for fasto-mode.  Is run whenever the mode is entered.")

(defvar fasto-mode-map
  (make-keymap)
  "Keymap for fasto-mode.")

(defconst fasto-keywords
  '("if" "then" "else" "let" "in" "fun" "fn" "op")
  "All FASTO keywords.")

(defconst fasto-builtin-functions
  '("iota" "replicate" "map" "reduce" "read" "write" "not")
  "All FASTO builtin SOACs, functions and non-symbolic operators.")

(defconst fasto-builtin-operators
  '("+" "-" "==" "<" "~" "&&" "||")
  "All FASTO builtin symbolic operators.")

(defconst fasto-types
  '("int" "bool" "char")
  "All FASTO types.")

(defconst fasto-booleans
  '("true" "false")
  "All FASTO booleans.")


;;; Highlighting

(defvar fasto-font-lock
  `(

    ;; Function declarations
    ("fun +[^ ]+ +\\([[:alpha:]][_[:alnum:]]*\\)"
     . '(1 font-lock-function-name-face))

    ;; Variable declarations
    ("let \\([[:alpha:]][_[:alnum:]]*\\)"
     . '(1 font-lock-variable-name-face))

    ;; Keywords
    (,(regexp-opt fasto-keywords 'words)
     . font-lock-keyword-face)

    ;; Types
    (,(regexp-opt fasto-types 'words)
     . font-lock-type-face)

    ;; Builtins
    ;;; Functions
    (,(regexp-opt fasto-builtin-functions 'words)
     . font-lock-builtin-face)
    ;;; Operators
    (,(regexp-opt fasto-builtin-operators)
     . font-lock-builtin-face)

    ;; Constants
    ;;; Characters
    ("'\\([^\\'\n]\\|\\\\[a-z']\\)'"
     . font-lock-constant-face)
    ;;; Booleans
    (,(regexp-opt fasto-booleans 'words)
     . font-lock-constant-face)

    )
  "Highlighting expressions for FASTO.")

(defvar fasto-mode-syntax-table
  ; This is horrible.
  (let ((st (make-syntax-table)))
    ;; Define the // line comment syntax.
    (modify-syntax-entry ?/ ". 124b" st)
    (modify-syntax-entry ?\n "> b" st)
    ;; Make '_' a word constitutent.
    (modify-syntax-entry ?_ "w" st)
    ;; Make "'" a proper quote character.
    (modify-syntax-entry ?' "\"" st)
    st)
  "Syntax table used in `fasto-mode'.")


;;; Indentation

(defun fasto-indent-line ()
  "Indent current line as FASTO code."
  (let ((savep (> (current-column) (current-indentation)))
        (indent (or (fasto-calculate-indentation)
                    (current-indentation))))
    (if savep ; The cursor is beyond leading whitespace.
        (save-excursion (indent-line-to indent))
      (indent-line-to indent))))

(defun fasto-calculate-indentation ()
  "Calculate the indentation for the current line.  In general,
prefer as little indentation as possible, and make block
constituents match each other's indentation."
  (let ((parse-sexp-lookup-properties t)
        (parse-sexp-ignore-comments t))

    (save-excursion
      (fasto-beginning-of-line-text)

      (or

       ;; Align comment to next non-comment line.
       (and (looking-at "//")
            (forward-comment (count-lines (point-min) (point)))
            (current-column))

       ;; Align function definitions to column 0.
       (and (fasto-looking-at-word "fun")
            0)

       ;; Align closing parentheses, commas and pipes to opening
       ;; parenthesis.
       (save-excursion
         (and (looking-at (regexp-opt '(")" "]" "}" "," "|")))
              (ignore-errors
                (backward-up-list 1)
                (current-column))))

       ;; Align "in" to nearest "let".
       (save-excursion
         (and (fasto-looking-at-word "in")
              (fasto-find-keyword-backward "let")
              (current-column)))

       ;; Align "then" to nearest "if" or "else if".
       (save-excursion
         (and (fasto-looking-at-word "then")
              (fasto-find-keyword-backward "if")
              (or
               (let ((curline (line-number-at-pos)))
                 (save-excursion
                   (and (fasto-backward-part)
                        (= (line-number-at-pos) curline)
                        (fasto-looking-at-word "else")
                        (current-column))))
               (current-column))))

       ;; Align "else" to nearest "then" or "if ... then" or
       ;; "else if ... then"
       (save-excursion
         (and (fasto-looking-at-word "else")
              (fasto-find-keyword-backward "then")
              (or
               (let ((curline (line-number-at-pos)))
                 (save-excursion
                   (and (fasto-find-keyword-backward "if")
                        (= (line-number-at-pos) curline)
                        (or (save-excursion (and (fasto-backward-part)
                                                 (= (line-number-at-pos) curline)
                                                 (fasto-looking-at-word "else")
                                                 (current-column)))
                            (current-column)))))
               (current-column))))

       ;; Align "=" to nearest "let".
       (save-excursion
         (and (looking-at "=[^=]")
              (fasto-find-keyword-backward "let")
              (current-column)))

       ;; Otherwise, if the previous code line ends with
       ;; "in" or "=", align to the matching "let".
       (save-excursion
         (and (fasto-backward-part)
              (or (looking-at "\\<in$")
                  (looking-at "=$"))
              (fasto-find-keyword-backward "let")
              (current-column)))

       ;; Otherwise, if inside a parenthetical structure, align to its
       ;; start element if present, otherwise the parenthesis + 1.
       (save-excursion
         (and (ignore-errors (backward-up-list 1) t)
              (ignore-errors (forward-char) t)
              (let ((linum (line-number-at-pos)))
                (or (save-excursion (and (ignore-errors (forward-sexp) t)
                                         (= (line-number-at-pos) linum)
                                         (ignore-errors (backward-sexp) t)
                                         (current-column)))
                    (current-column)))))

       ;; Otherwise, if the previous keyword is "fun", align to
       ;; 2.
       (and
        (string= "fun" (save-excursion (fasto-first-keyword-backward)))
        2)

       ;; Otherwise, align to the previous line.
       (save-excursion
         (and (= 0 (forward-line -1))
              (progn (fasto-beginning-of-line-text) t)
              (current-column)))

       ))))

(defun fasto-beginning-of-line-text ()
  "Move to the beginning of the text on this line.  Contrary to
`beginning-of-line-text', consider any non-whitespace character
to be text."
  (beginning-of-line)
  (while (looking-at " ")
    (forward-char)))

(defun fasto-backward-part ()
  "Try to jump back one sexp.  The net effect seems to be that it
works ok."
  (and (not (bobp))
       (ignore-errors (backward-sexp 1) t)))

(defun fasto-looking-at-word (word)
  (looking-at (concat "\\<" word "\\>")))

(defun fasto-find-keyword-backward (word)
  "Find a keyword before the current position.  Set mark and
return t if found; return nil otherwise."
  (let ((pstart (point))
        ;; We need to count "if"s, "then"s and "else"s to properly
        ;; indent.
        (if-else-count 0)
        (then-else-count 0)
        ;; The same with "let" and "in".
        (let-in-count 0)
        ;; Only look in the current paren-delimited code.
        (topp (save-excursion (or (ignore-errors
                                    (backward-up-list 1)
                                    (point))
                                  (fasto-find-keyword-backward-raw "fun")
                                  0)))
        (result nil)
        )

    (cond ((fasto-looking-at-word "else")
           (incf if-else-count)
           (incf then-else-count))
          ((fasto-looking-at-word "in")
           (incf let-in-count))
          )

    (while (and (not result)
                (fasto-backward-part)
                (>= (point) topp))
      (cond ((fasto-looking-at-word "if")
             (setq if-else-count (max 0 (1- if-else-count))))
            ((fasto-looking-at-word "then")
             (setq then-else-count (max 0 (1- then-else-count))))
            ((fasto-looking-at-word "else")
             (incf if-else-count)
             (incf then-else-count))
            ((fasto-looking-at-word "let")
             (setq let-in-count (max 0 (1- let-in-count))))
            ((fasto-looking-at-word "in")
             (incf let-in-count))
            )

      (when (and (fasto-looking-at-word word)
                 (or (and (string= "if" word)
                          (= 0 let-in-count)
                          (= 0 if-else-count))
                     (and (string= "then" word)
                          (= 0 let-in-count)
                          (= 0 then-else-count))
                     (and (string= "else" word)
                          (= 0 let-in-count))
                     (and (string= "let" word)
                          (= 0 let-in-count))
                     (string= "in" word)
                     (string= "fun" word)
                     ))
        (setq result (point))
        ))

    (if result
        result
      (goto-char pstart)
      nil)
    ))

(defun fasto-find-keyword-backward-raw (word)
  "Find a keyword before the current position, but ignore any
program structure."
  (let ((pstart (point)))
    (while (and (fasto-backward-part)
                (not (fasto-looking-at-word word))))
    (if (fasto-looking-at-word word)
        (point)
      (goto-char pstart)
      nil)))

(defun fasto-first-keyword-backward ()
  "Going backwards, find the first FASTO keyword."
  (while (and (fasto-backward-part)
              (not (some 'fasto-looking-at-word fasto-keywords))))

  (some (lambda (kwd)
          (and (fasto-looking-at-word kwd)
               kwd))
        fasto-keywords))


;;; Actual mode declaration

(define-derived-mode fasto-mode fundamental-mode "FASTO"
  "Major mode for editing FASTO source files."
  :syntax-table fasto-mode-syntax-table
  (set (make-local-variable 'font-lock-defaults) '(fasto-font-lock))
  (set (make-local-variable 'indent-line-function) 'fasto-indent-line)
  (set (make-local-variable 'indent-region-function) nil)
  (set (make-local-variable 'comment-start) "//")
  (set (make-local-variable 'comment-padding) " "))


;;; Interactive functions, keybindings and related parts

(defvar fasto-output-font-lock
  (append
   '(
     ("Program is:" . font-lock-comment-face)
     ("+--.+" . font-lock-comment-face)
     ("^|" . font-lock-comment-face)
     ("|$" . font-lock-comment-face)
     ("Result of .+" . font-lock-comment-face)
     )
   fasto-font-lock))

(define-derived-mode fasto-output-mode fasto-mode "fasto output"
  "Major mode for viewing FASTO interpreter output."
  (set (make-local-variable 'font-lock-defaults) '(fasto-output-font-lock)))

(defvar fasto-binary nil
  "The global location of the fasto binary.")

(defun fasto-interpret (file &optional fasto-bin)
  "Interpret a FASTO file.  If called interactively, guess the
path of the binary 'fasto' and run that on the file of the
current buffer.

`file' is the file to interpret.

`fasto-bin' is the location of the binary.  If not set,
`fasto-binary' will be used, or the path will be guessed if that
is nil.
"
  (interactive (list (buffer-file-name)))
  ; In the handed out code, tests are located in "src/", and the
  ; binary in "bin/", so we assume this is the case here.
  (let ((bufname "*FASTO interpreter output*")
        (max-mini-window-height 0)
        (fasto-bin (or fasto-bin
                       fasto-binary
                       (concat (file-name-directory file) "../bin/fasto"))))
    (shell-command
     (concat fasto-bin " -i " file) bufname)
    ; Set the mode of the new buffer.
    (with-current-buffer bufname
      (fasto-output-mode))))

(define-key fasto-mode-map (kbd "C-c C-l") 'fasto-interpret)


(provide 'fasto-mode)

;;; fasto-mode.el ends here
