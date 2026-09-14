#lang racket/base

;; Error surface of the safe layer. The shim records failures on
;; bezel_last_error; these helpers turn nonzero/zero statuses and null
;; returns into exn:fail:bezel with that message attached.

(provide (struct-out exn:fail:bezel)
         raise-bezel-error
         last-error
         ok!
         ok-handle
         ok-string
         require-application
         current-application
         set-current-application!)

(require (only-in "raw.rkt" bezel-last-error))

(struct exn:fail:bezel exn:fail ())

(define (last-error)
  (define msg (bezel-last-error))
  (and msg (not (equal? "" msg)) msg))

(define (raise-bezel-error who)
  (raise
   (exn:fail:bezel
    (format "bezel: ~a: ~a" who (or (last-error) "unknown error"))
    (current-continuation-marks))))

;; Raise unless the raw call returned 1.
(define (ok! who result)
  (unless (= 1 result) (raise-bezel-error who))
  (void))

;; Raise on a null handle return (Racket FFI maps NULL pointers to #f).
(define (ok-handle who handle)
  (unless handle (raise-bezel-error who))
  handle)

;; Raise on a null string return; returns the raw pointer (caller frees).
(define (ok-string who pointer)
  (unless pointer (raise-bezel-error who))
  pointer)

;; The single QApplication, tracked by app.rkt. Constructors consult
;; this so "forgot make-application" fails with guidance instead of a
;; Qt runtime warning.
(define the-application #f)

(define (current-application) the-application)

(define (set-current-application! app) (set! the-application app))

(define (require-application)
  (unless the-application
    (raise
     (exn:fail:bezel
      "bezel: no application — call (make-application) before creating widgets"
      (current-continuation-marks)))))
