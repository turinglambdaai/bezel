#lang racket/base

;; Menus: menu-bar on a window, menus (and submenus), actions.

(provide menu-bar menu! menu-action! menu-separator! set-action-shortcut!
         window-status-bar
         status-show-message!
         status-clear-message!
         status-current-message
         window-toolbar
         toolbar-add-action!)

(require "private/errors.rkt"
         "private/objects.rkt"
         "private/raw.rkt")

;; The window's menu bar (created on first call).
(define (menu-bar win)
  (require-alive! 'menu-bar win)
  (wrap-handle (ok-handle 'menu-bar (bezel-menubar (ptr-of win))) 'widget #f))

;; Add a menu to a menu bar — or a submenu to a menu:
;;   (define file (menu! bar "File"))
;;   (define recent (menu! file "Open Recent"))
(define (menu! parent title)
  (require-alive! 'menu! parent)
  (wrap-handle (ok-handle 'menu! (bezel-menu-add (ptr-of parent) title)) 'menu #f))

;; Add an action item; connect "triggered()" on the result.
(define (menu-action! menu text)
  (require-alive! 'menu-action! menu)
  (wrap-handle (ok-handle 'menu-action! (bezel-menu-action (ptr-of menu) text)) 'action #f))

(define (menu-separator! menu)
  (require-alive! 'menu-separator! menu)
  (bezel-menu-separator (ptr-of menu))
  (void))

;; Keyboard shortcut for a menu action, e.g. "Ctrl+Q" (QKeySequence
;; text). An empty string clears the shortcut.
(define (set-action-shortcut! action key)
  (require-alive! 'set-action-shortcut! action)
  (ok! 'set-action-shortcut! (bezel-action-set-shortcut (ptr-of action) key)))

;; ---- window chrome ----------------------------------------------------------

;; The window's status bar (created on first call).
(define (window-status-bar win)
  (require-alive! 'window-status-bar win)
  (wrap-handle (ok-handle 'window-status-bar (bezel-window-statusbar (ptr-of win)))
               'widget #f))

;; Show a transient message; timeout-ms 0 keeps it until replaced/cleared.
(define (status-show-message! sb message [timeout-ms 0])
  (require-alive! 'status-show-message! sb)
  (ok! 'status-show-message! (bezel-status-show-message (ptr-of sb) message timeout-ms)))

(define (status-clear-message! sb)
  (require-alive! 'status-clear-message! sb)
  (ok! 'status-clear-message! (bezel-status-clear-message (ptr-of sb))))

(define (status-current-message sb)
  (require-alive! 'status-current-message sb)
  (define p (ok-string 'status-current-message (bezel-status-current-message (ptr-of sb))))
  (begin0 (cstring->string/utf8 p)
    (bezel-free p)))

;; Add a tool bar to a window; returns the QToolBar.
(define (window-toolbar win title)
  (require-alive! 'window-toolbar win)
  (wrap-handle (ok-handle 'window-toolbar (bezel-window-toolbar (ptr-of win) title))
               'widget #f))

;; Add a button-like action to a tool bar; connect "triggered()" on it.
(define (toolbar-add-action! toolbar text)
  (require-alive! 'toolbar-add-action! toolbar)
  (wrap-handle (ok-handle 'toolbar-add-action! (bezel-toolbar-add-action (ptr-of toolbar) text))
               'action #f))
