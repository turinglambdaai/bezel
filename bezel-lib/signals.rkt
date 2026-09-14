#lang racket/base

;; Signals: connect Racket procedures to Qt signals.
;;
;;   (connect! button "clicked()" (lambda args (displayln "clicked!")))
;;   (connect! slider "valueChanged(int)" (lambda (v) (displayln v)))
;;
;; The handler runs on Bezel's dispatcher Racket thread. Plain Racket
;; code works there; widget calls are marshaled to the Qt GUI thread by
;; the shim, so handlers may freely mix both. Signal handlers must not
;; block indefinitely — spawn a thread for long work.
;;
;; Typed signals (those whose first argument Bezel converts — bool, int,
;; QString) pass the argument to the handler; other signals invoke it
;; with no arguments.

(provide connect! disconnect! emit-test-signal!)

(require ffi/unsafe
         ffi/unsafe/cvector
         racket/list
         "private/ctypes.rkt"
         "private/dispatch.rkt"
         "private/errors.rkt"
         "private/objects.rkt"
         "private/raw.rkt")

;; Connect `handler` to `signal` (Qt normalized signature, e.g.
;; "clicked()"). Returns the connection id (truthy) for disconnect!.
(define (connect! target signal handler)
  (require-alive! 'connect! target)
  (unless (procedure? handler)
    (raise-argument-error 'connect! "procedure?" handler))
  (define conn-id (bezel-connect (ptr-of target) signal))
  (when (zero? conn-id) (raise-bezel-error 'connect!))
  (ensure-dispatcher!)
  (register-handler! conn-id handler)
  conn-id)

(define (disconnect! target conn-id)
  (require-alive! 'disconnect! target)
  (unregister-handler! conn-id)
  (ok! 'disconnect! (bezel-disconnect (ptr-of target) conn-id)))

;; ---- test hook ---------------------------------------------------------------

;; Emit `signal` on `target` as if Qt did, exercising the full bridge
;; (queue, dispatcher thread, handler). This is how the CI e2e tests
;; click buttons without a human — the Racket-side counterpart of
;; glaze's agent-friendly verification.
;;
;;   (emit-test-signal! btn "clicked()")
;;   (emit-test-signal! slider "valueChanged(int)" (list 42))
;;
;; Args support: exact integers, booleans, reals, strings.
(define (emit-test-signal! target signal [args '()])
  (require-alive! 'emit-test-signal! target)
  (define argc (length args))
  (define vec (make-cvector _bezel-variant argc))
  (for ([a (in-list args)] [i (in-naturals)])
    (cvector-set! vec i (value->variant a)))
  (ok! 'emit-test-signal!
       (bezel-signal-emit (ptr-of target) signal argc (cvector-ptr vec))))

(define (value->variant a)
  (cond
    [(exact-integer? a)
     (make-bezel-variant a 0.0 #f #f +vt-int+)]
    [(boolean? a)
     (make-bezel-variant (if a 1 0) 0.0 #f #f +vt-bool+)]
    [(real? a)
     (make-bezel-variant 0 (exact->inexact a) #f #f +vt-double+)]
    [(string? a)
     (define b (string->bytes/utf-8 a))
     (define p (malloc (add1 (bytes-length b)) 'raw))
     (memcpy p b (bytes-length b))
     (ptr-set! p _ubyte (bytes-length b) 0)  ; NUL-terminate
     (make-bezel-variant 0 0.0 #f p +vt-string+)]
    [else
     (raise-argument-error 'emit-test-signal! "(or/c exact-integer? boolean? real? string?)" a)]))
