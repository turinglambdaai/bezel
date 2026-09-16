#lang racket/base

;; Application lifecycle: make-application, run, quit!.

(provide (struct-out application-token)
         make-application
         run
         quit!
         process-events!
         set-quit-on-last-window-closed!
         bezel-cleanup!)

(require "private/errors.rkt"
         "private/marshal.rkt"
         "private/raw.rkt"
         "widgets.rkt")

;; Opaque marker for the QApplication. The C side owns the real object;
;; Racket only tracks existence, so there is no handle to finalize.
(struct application-token (name) #:transparent)

;; Exit code requested via quit! and reported by run. Window-close
;; exits report 0 (run resets this at entry).
(define quit-code 0)

;; Create the QApplication. Idempotent — later calls return the existing
;; application (call again after bezel-cleanup! to start a new one).
;; Must run once at startup, before creating any widget.
(define (make-application #:name [name #f])
  (or (current-application)
      (let ([app (application-token name)])
        (ok! 'make-application (bezel-app-new name))
        (set-current-application! app)
        app)))

;; Run the application until quit!.
;;
;; The event loop is a pump: short foreign processEvents calls alternate
;; with Racket scheduler yields. A blocking QApplication::exec would pin
;; the main thread in foreign code forever, and Racket threads are
;; cooperatively scheduled — the signal dispatcher would never run and
;; no handler would ever fire. The pump keeps both worlds alive; the
;; main thread also stays the process main thread (a macOS requirement
;; for GUI work).
;;
;;   (define win (make-window #:title "Hello" #:size '(320 140)))
;;   (run win)
;;
;; Returns the code passed to quit! and releases application state.
(define (run [win #f] #:fps [fps 60.0])
  (make-application)
  (when win (widget-show! win))
  (set! quit-code 0)  ; window-close exits report 0 unless quit! runs
  (define frame (/ 1.0 fps))
  (let loop ()
    (bezel-process-events 30)   ; pump Qt events (bounded foreign call)
    (drain-gui!)                ; run calls marshaled from other threads
    (sleep frame)               ; yield: the dispatcher delivers handlers
    (unless (= 1 (bezel-app-quit-requested)) (loop)))
  (begin0 quit-code
    (bezel-cleanup!)))

;; Ask the running application to stop; `run` then returns `code`.
(define (quit! [code 0])
  (set! quit-code code)
  (ok! 'quit! (bezel-app-quit code)))

;; Toggle whether the pump stops once a shown window is no longer
;; visible (the pump-loop equivalent of Qt's
;; quit-on-last-window-closed). On by default.
(define (set-quit-on-last-window-closed! enabled?)
  (ok! 'set-quit-on-last-window-closed!
       (bezel-app-set-quit-on-last-window-closed (if enabled? 1 0))))

;; Pump the event loop for up to `ms` milliseconds without blocking in
;; exec — used by offscreen tests and non-blocking loops.
(define (process-events! [ms 50])
  (ok! 'process-events! (bezel-process-events ms))
  (drain-gui!))

;; Release application-level state (flush deferred deletions, destroy
;; the QApplication). `run` does this automatically; idempotent.
(define (bezel-cleanup!)
  (ok! 'bezel-cleanup! (bezel-cleanup))
  (set-current-application! #f))
