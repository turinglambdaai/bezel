#lang racket/base

;; Timers: schedule Racket procedures without owning a Qt event loop.
;;
;;   (after! 500 (lambda () (widget-set-text! status "done")))
;;   (define clock (every! 100 (lambda () (widget-set-value! bar (tick)))))
;;   ...
;;   (stop-timer! clock)
;;
;; Handlers run on their own Racket thread, not the dispatcher: plain
;; computation is fine there, and widget calls marshal to the GUI thread
;; like any other cross-thread call. Pending timers do not keep `run`
;; alive; after bezel-cleanup! a late handler fails normally (no
;; application), so stop timers before teardown when that matters.
;;
;; after!: an exception in the handler cancels that timer. every!: an
;; exception is reported to current-error-port and the interval keeps
;; firing — one bad tick must not silently kill a clock.

(provide after!
         every!
         stop-timer!
         bezel-timer?
         bezel-timer-running?)

;; A timer is a cancellable running flag: the worker thread checks it
;; between slices, so stop-timer! takes effect without killing a
;; handler that is mid-flight. The flag field is named on? because a
;; mutable field named running? would hijack the natural predicate
;; name (struct field accessors shadow user definitions).
(struct bezel-timer ([on #:mutable]) #:transparent)

(define (bezel-timer-running? timer)
  (bezel-timer-on timer))

;; Sleep in slices so stop-timer! is honored promptly; a plain (sleep s)
;; would ignore a stop request for the whole interval.
(define (sleep-until-stopped! timer seconds)
  (define deadline (+ (current-inexact-milliseconds) (* seconds 1000.0)))
  (let loop ()
    (when (and (bezel-timer-on timer)
               (< (current-inexact-milliseconds) deadline))
      (sleep (min 0.05
                  (max 0.0 (/ (- deadline (current-inexact-milliseconds)) 1000.0))))
      (loop))))

(define (check-milliseconds! who ms)
  (unless (and (real? ms) (rational? ms) (>= ms 0))
    (raise-argument-error who "nonnegative real number (milliseconds)" ms)))

;; Run `thunk` once after `ms` milliseconds.
(define (after! ms thunk)
  (check-milliseconds! 'after! ms)
  (unless (procedure? thunk)
    (raise-argument-error 'after! "procedure?" thunk))
  (define timer (bezel-timer #t))
  (thread
   (lambda ()
     (sleep-until-stopped! timer (/ ms 1000.0))
     (when (bezel-timer-on timer)
       (set-bezel-timer-on! timer #f)
       (with-handlers ([exn? (lambda (e)
                               (eprintf "bezel: after! handler raised: ~a\n"
                                        (exn-message e)))])
         (thunk)))))
  timer)

;; Run `thunk` every `ms` milliseconds until stop-timer!.
(define (every! ms thunk)
  (check-milliseconds! 'every! ms)
  (unless (procedure? thunk)
    (raise-argument-error 'every! "procedure?" thunk))
  (define timer (bezel-timer #t))
  (thread
   (lambda ()
     (let loop ()
       (sleep-until-stopped! timer (/ ms 1000.0))
       (when (bezel-timer-on timer)
         (with-handlers ([exn? (lambda (e)
                                 (eprintf "bezel: every! handler raised: ~a\n"
                                          (exn-message e)))])
           (thunk))
         (loop)))))
  timer)

;; Stop a pending timer. A handler that is already running is never
;; aborted mid-flight; stop-timer! only prevents later firings.
(define (stop-timer! timer)
  (unless (bezel-timer? timer)
    (raise-argument-error 'stop-timer! "bezel-timer?" timer))
  (set-bezel-timer-on! timer #f))
