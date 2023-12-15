(require 'package)
(add-to-list 'package-archives '("gnu"   . "https://elpa.gnu.org/packages/"))
(add-to-list 'package-archives '("melpa" . "https://melpa.org/packages/"))
(package-refresh-contents)

;; Set up use-package
(unless (package-installed-p 'use-package)
  (package-refresh-contents)
  (package-install 'use-package))
(eval-and-compile
  (setq use-package-always-ensure t
        use-package-expand-minimally t))

;; ====
;; EVIL
;; ====

(use-package evil
  :ensure t
  :init
  (setq evil-want-keybinding nil)
  :config
  (evil-mode 1))

(use-package evil-collection
  :ensure t
  :config
  (evil-collection-init))

;; =============
;; DOOM MODELINE
;; =============

(use-package doom-modeline
  :ensure t
  :config
  (doom-modeline-mode 1)
  (setq doom-modeline-enable-word-count t)
  (setq doom-modeline-icon t)
  (setq doom-modeline-indent-info nil)
  (setq doom-modeline-minor-modes nil)
  (setq doom-modeline-modal t)
  (display-battery-mode)
  (setq doom-modeline-battery t)
  (display-time-mode)
  (setq doom-modeline-time t))

;; ====
;; HELM
;; ====

(use-package helm
  :ensure t
  :config
  (helm-mode 1)
  (global-set-key (kbd "M-x") 'helm-M-x)
  (global-set-key (kbd "C-x C-f") 'helm-find-files)
  (global-set-key (kbd "C-x b") 'helm-mini))

;; ==============
;; GLOBAL SETTINGs
;; ==============

;; set frame title format
(setq frame-title-format "%b [%m] - Emacs")

(use-package nerd-icons
  :ensure t)

(add-to-list 'default-frame-alist '(font . "Hasklug Nerd Font-14"))
(set-frame-font "Hasklug Nerd Font-14" nil t)

(use-package doom-themes
  :ensure t
  :config
  ;; Global settings (defaults)
  (setq doom-themes-enable-bold t
        doom-themes-enable-italic t)
  (load-theme 'doom-one t))

(menu-bar-mode -1)                   ;; hide menubar
(tool-bar-mode -1)                   ;; hide toolbar
(scroll-bar-mode -1)                 ;; hide scrollbar
(global-display-line-numbers-mode)   ;; show line numbers
(show-paren-mode 1)                  ;; highlight matching parentheses
(blink-cursor-mode 0)                ;; disable blinking cursor

(setq make-backup-files nil)         ;; disable backups

;; Show keybinding hints
(use-package which-key
  :ensure t
  :config
  (which-key-mode))

(electric-pair-mode 1)               ;; auto close parentheses
(setq-default indent-tabs-mode nil)  ;; use spaces instead of tabs
(setq tab-width 2)                   ;; set tab width to 2

;; flash the modeline instead of sounding the bell
(use-package mode-line-bell
  :ensure t
  :config
  (mode-line-bell-mode))

(defcustom display-line-numbers-exempt-modes
  '(vterm-mode eshell-mode shell-mode term-mode ansi-term-mode)
  "Major modes on which to disable line numbers."
  :group 'display-line-numbers
  :type 'list
  :version "green")

(defun display-line-numbers--turn-on ()
  "Turn on line numbers except for certain major modes.
Exempt major modes are defined in `display-line-numbers-exempt-modes'."
  (unless (or (minibufferp)
              (member major-mode display-line-numbers-exempt-modes))
    (display-line-numbers-mode)))

(global-display-line-numbers-mode)
(setq display-line-numbers 'relative)

;; attempt to work around a bug in lsp-mode
; (setq max-lisp-eval-depth 10000)

(use-package undo-tree
  :ensure t
  :config
  (global-undo-tree-mode))

(use-package flycheck
  :ensure t
  :config
  (global-flycheck-mode))

(use-package company
  :ensure t
  :config
  (global-company-mode))

(use-package helm-lsp
  :ensure t)

(use-package magit
  :ensure t)

;; =============
;; CENTATUR TABS
;; =============

(use-package centaur-tabs
  :ensure t
  :demand
  :after (general)
  :config
  (centaur-tabs-mode t)
  (setq centaur-tabs-style "bar")
  (setq centaur-tabs-set-icons t)
  (setq centaur-tabs-set-bar 'over)
  (setq centaur-tabs-set-modified-marker t)
  (general-define-key
   "C-<tab>" 'centaur-tabs-forward
   "C-S-<tab>" 'centaur-tabs-backward)
  (general-define-key
   :states '(normal)
   "g t" 'centaur-tabs-forward
   "g T" 'centaur-tabs-backward))

;; (use-package treemacs
;;   :ensure t)

;; (use-package treemacs-evil
;;   :after (treemacs evil)
;;   :ensure t)

;; (use-package treemacs-icons-dired
;;   :hook (dired-mode . treemacs-icons-dired-enable-once)
;;   :ensure t)

;; (use-package treemacs-magit
;;   :after (treemacs magit)
;;   :ensure t)

;; ==================
;; GLOBAL KEYBINDINGS
;; ==================

(use-package general
  :ensure t
  :config
  (general-auto-unbind-keys)
  (general-define-key
   :states '(normal visual)
   "j" 'evil-next-visual-line
   "k" 'evil-previous-visual-line)

  (general-create-definer ag/leader-keys
    :states '(normal visual insert emacs)
    :prefix "SPC"
    :global-prefix "M-SPC")

  (ag/leader-keys
   "b" '(ignore t :wk "buffer")
   "b b" '(helm-mini :wk "Switch")
   "b k" '(kill-buffer :wk "Kill")
   "b r" '(rename-buffer :wk "Rename")
   "b t" '(unique-eshell :wk "Shell")
   "b j" '(new-jounal-entry :wk "Journal")
   "b e" '(eval-buffer :wk "Eval"))

  (ag/leader-keys
    "f" '(ignore t :wk "file")
    "f d" '(dired :wk "dired")
    "f f" '(helm-find-files :wk "find")
    "f s" '(save-buffer :wk "save"))

  (ag/leader-keys
    "h" '(ignore t :wk "help")
    "h k" '(describe-key :wk "describe key")
    "h f" '(describe-function :wk "describe function")
    "h v" '(describe-variable :wk "describe variable")
    "h r" '((lambda () (interactive) (load-file user-init-file)) :wk "reload config"))

  (ag/leader-keys
    "a" '(ignore t :wk "todo")
    "a u" '(undo-tree-visualize :wk "Undo tree"))

  (ag/leader-keys
    "r" '(ignore t :wk "register")
    "r y" '(copy-to-register :wk "Copy")
    "r p" '(insert-register :wk "Paste")
    "r a" '(append-to-register :wk "Append")
    "r r" '(point-to-register :wk "Point")
    "r j" '(jump-to-register :wk "Jump")
    "r w" '(window-configuration-to-register :wk "Window"))

  (ag/leader-keys
    "w" '(ignore t :wk "window")
    "w h" '(windmove-left :wk "Left")
    "w j" '(windmove-down :wk "Down")
    "w k" '(windmove-up :wk "Up")
    "w l" '(windmove-right :wk "Right")
    "w d" '(delete-window :wk "Delete this")
    "w o" '(delete-other-windows :wk "Delete others")
    "w b" '(split-window-below :wk "Split below")
    "w r" '(split-window-right :wk "Split right"))

  (ag/leader-keys
    "/" '(comment-line :wk "comment")))

;; ===
;; LSP
;; ===

(use-package lsp-mode
  :ensure t
  :hook (;(haskell-mode . #'lsp)
         (python-mode . #'lsp)))

;; ========
;; MARKDOWN
;; ========

(use-package markdown-mode
  :ensure t
  :after (general)
  :hook ((markdown-mode . flyspell-mode)
         (markdown-mode . pandoc-mode)
         (markdown-mode . texfrag-mode))
  :config
  (setq markdown-code-block-braces t)
  (setq markdown-enable-highlighting-syntax t)
  (setq markdown-enable-math t)
  (setq markdown-enable-wiki-links t)
  (setq markdown-hide-markup t)
  (setq markdown-hide-urls nil)
  (setq markdown-list-indent-width 2)
  (setq markdown-fontify-code-blocks-natively t)

  (general-define-key
   :keymaps 'markdown-mode-map
   "<tab>" 'markdown-cycle)     ;; TAB should always cycle

  ;; Ergonomic promotion/demotion from normal state in markdown-mode
  (general-define-key
   :states 'normal
   :keymaps 'markdown-mode-map
   "H" 'markdown-promote
   "L" 'markdown-demote)
  
  (ag/leader-keys
    :keymaps 'markdown-mode-map
    "m" '(ignore t :wk "markdown")

    "m p" '(pandoc-main-hydra/body :wk "pandoc")

    "m f" '(ignore t :wk "format")
    "m f i" '(markdown-insert-italic :wk "italic")
    "m f b" '(markdown-insert-bold :wk "bold")
    "m f u" '(markdown-insert-link :wk "link")))
;
;(general-define-key
; :keymaps 'markdown-mode-map
; :states '(normal insert)
; :prefix "SPC"
; :non-normal-prefix "M-SPC"
; "l b" 'markdown-insert-latex-block
; "l i" 'markdown-insert-latex-inline
; "p" 'texfrag-document)

(defun new-jounal-entry ()
  "Open today's journal entry, and populate it if it doesn't already exist."
  (interactive)
  (find-file (concat "~/Nextcloud/notes/journal/" (format-time-string "%Y-%m-%d") ".md"))
  (cond ((= (buffer-size) 0)
         (insert "---\n")
         (insert (concat "date: " (format-time-string "%Y-%m-%d") "\n"))
         (insert "mood: \n")
         (insert "---\n\n")
         (insert "# 3 things I'm grateful for\n\n")
         (insert "# What went well today\n\n")
         (insert "# What didn't go well today\n\n")
         (insert "# Misc thoughts\n\n\n"))))

;; =====
;; LATEX
;; =====

;; Spellcheck
(add-hook 'latex-mode-hook 'flyspell-mode)

; (general-define-key
;  :keymaps 'latex-mode-map
;  :states 'insert
;  "M-RET" 'LaTeX-insert-item)

;; ======
;; RACKET
;; ======

(use-package racket-mode
  :ensure t)

; (general-define-key
;  :keymaps 'racket-mode-map
;  "C-c C-a" 'racket-align)
; 
; (general-define-key
;  :keymaps 'racket-debug-mode-map
;  :prefix "C-c d"
;  "r" 'racket-run-with-debugging
;  "s" 'racket-debug-step
;  "c" 'racket-debug-continue
;  "o" 'racket-debug-step-out
;  "v" 'racket-debug-step-over
;  "h" 'racket-debug-run-to-here
;  "n" 'racket-debug-next-breakable
;  "p" 'racket-debug-prev-breakable
;  "d" 'racket-debug-disable)

;; =======
;; HASKELL
;; =======

(use-package haskell-mode
  :ensure t
  :hook ((haskell-mode . interactive-haskell-mode)
         (haskell-mode . #'lsp-deferred))
  )
  ;; :config
  ;; ; for some reason this isn't picked up automatically
  ;; (add-to-list 'auto-mode-alist '("\\.hs\\'" . haskell-mode)))

;; =====
;; DIRED
;; =====

;; From dired, open a file externally
(defun dired-open-file ()
  (interactive)
  (let* ((file (dired-get-filename nil t)))
    (message "Opening %s..." file)
    (if (eq system-type 'darwin)
        (call-process "open" nil 0 nil file)
      (call-process "xdg-open" nil 0 nil file))
    (message "Opening %s done" file)))
; (general-define-key
;  :keymaps 'dired-mode-map
;  "e" 'dired-open-file)

;; Sort by directories first
(setq insert-directory-program "gls" dired-use-ls-dired t)
(setq dired-listing-switches "-al --group-directories-first")

;; ===
;; CSL
;; ===

;; Use xml-mode for CSL files
(add-to-list 'auto-mode-alist '("\\.csl\\'" . xml-mode))

;; =====
;; ESHELL
;; =====

;; Open a terminal and give it a unique name so we can have multiple terminals
(defun unique-eshell ()
  (interactive)
  (call-interactively 'eshell)
  (rename-uniquely))

(use-package eshell-syntax-highlighting
  :ensure t
  :after esh-mode
  :config
  (eshell-syntax-highlighting-global-mode 1))

;; ======
;; GOLANG
;; ======

(use-package go-mode
  :ensure t
  :config
  (add-hook 'go-mode-hook (lambda () (setq tab-width 2))))

;; ===============
;; EMACS CUSTOMIZE
;; ===============

;(custom-set-faces
 ;; custom-set-faces was added by Custom.
 ;; If you edit it by hand, you could mess it up, so be careful.
 ;; Your init file should contain only one such instance.
 ;; If there is more than one, they won't work right.
 ;'(markdown-header-face-2 ((t (:inherit markdown-header-face :foreground "deep sky blue" :height 1.0))))
 ;'(markdown-header-face-3 ((t (:inherit markdown-header-face :foreground "green" :height 1.0))))
 ;'(markdown-header-face-4 ((t (:inherit markdown-header-face :foreground "violet" :height 1.0))))
 ;'(markdown-header-face-5 ((t (:inherit markdown-header-face :foreground "dark turquoise" :height 1.0))))
 ;'(markdown-header-face-6 ((t (:inherit markdown-header-face :foreground "green yellow" :height 1.0))))
 ;'(org-latex-and-related ((t (:foreground "lawn green" :weight normal)))))
(custom-set-variables
 ;; custom-set-variables was added by Custom.
 ;; If you edit it by hand, you could mess it up, so be careful.
 ;; Your init file should contain only one such instance.
 ;; If there is more than one, they won't work right.
 '(column-number-mode t)
 '(custom-safe-themes
   '("2f1518e906a8b60fac943d02ad415f1d8b3933a5a7f75e307e6e9a26ef5bf570" default))
 '(dashboard-item-generators
   '((recents . dashboard-insert-recents)
     (bookmarks . dashboard-insert-bookmarks)
     (projects . dashboard-insert-projects)
     (registers . dashboard-insert-registers)))
 '(dashboard-items '((recents . 20) (bookmarks . 5) (agenda . 5)))
 '(evil-undo-system 'undo-tree)
 '(evil-want-Y-yank-to-eol t)
 '(global-undo-tree-mode t)
 '(haskell-completing-read-function 'helm--completing-read-default)
 '(helm-minibuffer-history-key "M-p")
 '(markdown-code-block-braces t)
 '(markdown-enable-highlighting-syntax t)
 '(markdown-enable-math t)
 '(markdown-enable-wiki-links t)
 '(markdown-hide-markup nil)
 '(markdown-hide-urls nil)
 '(markdown-list-indent-width 2)
 '(org-M-RET-may-split-line nil)
 '(org-babel-python-command "python3")
 '(org-hide-leading-stars t)
 '(org-highlight-latex-and-related '(latex script entities))
 '(org-list-allow-alphabetical t)
 '(org-pretty-entities t)
 '(package-selected-packages
   '(sudo-edit nix-mode go-mode treemacs-magit treemacs-icons-dired treemacs-evil doom eshell-syntax-highlighting mu4easy nerd-icons evil-collection magit company company-mode use-package undo-tree racket-mode ob-async pyvenv org-ref pdf-tools jupyter mode-line-bell lsp-haskell helm-lsp flycheck lsp-ui lsp-mode general which-key vterm yaml-mode dashboard texfrag edit-indirect haskell-mode auctex helm pandoc-mode markdown-mode doom-modeline doom-themes evil))
 '(warning-suppress-types '(((evil-collection))))
 '(which-key-frame-max-height 40)
 '(which-key-idle-delay 0.1))
(put 'downcase-region 'disabled nil)
(custom-set-faces
 ;; custom-set-faces was added by Custom.
 ;; If you edit it by hand, you could mess it up, so be careful.
 ;; Your init file should contain only one such instance.
 ;; If there is more than one, they won't work right.
 )
