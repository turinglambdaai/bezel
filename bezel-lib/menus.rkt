#lang racket/base

;; Menus: menu-bar on a window, menus (and submenus), actions.

(provide menu-bar menu! menu-action! menu-separator!)

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
