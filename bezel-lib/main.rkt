#lang racket/base

;; Bezel — Qt 6 bindings for Racket.
;;
;;   (require bezel)
;;
;;   (define win (make-window #:title "Hello" #:size '(320 140)))
;;   (define count (make-label "Clicked 0 times"))
;;   (define n (box 0))
;;   (define btn (make-button "Click me"))
;;   (connect! btn "clicked()" (lambda _
;;     (set-box! n (add1 (unbox n)))
;;     (widget-set-text! count (format "Clicked ~a times" (unbox n)))))
;;   (layout! win (vbox count btn))
;;   (run win)

(require "app.rkt"
         "dialogs.rkt"
         "generated/dial_gen.rkt"
         "layouts.rkt"
         "menus.rkt"
         "private/errors.rkt"
         "private/objects.rkt"
         "signals.rkt"
         "widgets.rkt")

(provide
 ;; application lifecycle
 (all-from-out "app.rkt")
 ;; widgets
 (all-from-out "widgets.rkt")
 ;; layouts
 (all-from-out "layouts.rkt")
 ;; generator-produced bindings (tools/generator)
 (all-from-out "generated/dial_gen.rkt")
 ;; menus
 (all-from-out "menus.rkt")
 ;; dialogs
 (all-from-out "dialogs.rkt")
 ;; signals
 (all-from-out "signals.rkt")
 ;; object model (bezel-alive?, bezel-delete!, object-name, ...)
 (all-from-out "private/objects.rkt")
 ;; error type (exn:fail:bezel? and friends)
 (all-from-out "private/errors.rkt"))
