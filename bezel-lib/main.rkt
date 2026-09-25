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
         "desktop.rkt"
         "dialogs.rkt"
         "sentry.rkt"
         "signals.rkt"
         "timers.rkt"
         "updates.rkt"
         "widgets.rkt"
         "generated/dial_gen.rkt"
         "generated/doublespin_gen.rkt"
         "generated/groupbox_gen.rkt"
         "generated/lcd_gen.rkt"
         "generated/radio_gen.rkt"
         "generated/richtext_gen.rkt"
         "generated/splitter_gen.rkt"
         "generated/stacked_gen.rkt"
         "generated/tabs_gen.rkt"
         "layouts.rkt"
         "menus.rkt"
         "observable.rkt"
         "private/errors.rkt"
         "private/objects.rkt")

(provide
 ;; application lifecycle
 (all-from-out "app.rkt")
 ;; widgets
 (all-from-out "widgets.rkt")
 ;; layouts
 (all-from-out "layouts.rkt")
 ;; generator-produced bindings (tools/generator)
 (all-from-out "generated/dial_gen.rkt")
 (all-from-out "generated/doublespin_gen.rkt")
 (all-from-out "generated/groupbox_gen.rkt")
 (all-from-out "generated/lcd_gen.rkt")
 (all-from-out "generated/radio_gen.rkt")
 (all-from-out "generated/richtext_gen.rkt")
 (all-from-out "generated/splitter_gen.rkt")
 (all-from-out "generated/stacked_gen.rkt")
 (all-from-out "generated/tabs_gen.rkt")
 ;; menus
 (all-from-out "menus.rkt")
 ;; observables (data binding)
 (all-from-out "observable.rkt")
 ;; dialogs
 (all-from-out "dialogs.rkt")
 ;; desktop integration (clipboard, system tray)
 (all-from-out "desktop.rkt")
 ;; error reporting (Sentry-compatible)
 (all-from-out "sentry.rkt")
 ;; signals
 (all-from-out "signals.rkt")
 ;; timers (after! / every! / stop-timer!)
 (all-from-out "timers.rkt")
 ;; update checks (check-for-update / check-and-prompt-update!)
 (all-from-out "updates.rkt")
 ;; object model (bezel-alive?, bezel-delete!, qt-object-name, ...)
 (all-from-out "private/objects.rkt")
 ;; error type (exn:fail:bezel? and friends)
 (all-from-out "private/errors.rkt"))
