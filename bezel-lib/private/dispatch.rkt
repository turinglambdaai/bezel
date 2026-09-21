#lang racket/base

;; The Racket side of the signal bridge.
;;
;; The shim queues delivered signals; this module owns the dispatcher
;; thread that drains bezel_next_signal and applies the registered
;; handler. Handlers run on the dispatcher Racket thread — plain Racket
;; code works there, and any bezel call is marshaled back onto the Qt
;; GUI thread by private/marshal.rkt.
;;
;; Handlers are kept strongly in `handlers` because the C side only
;; knows the numeric connection id. The shim emits an internal negative
;; connection-id notice when a target QObject dies; those notices retire
;; the matching Racket handler so long-running apps do not accumulate
;; dead callbacks.

(provide ensure-dispatcher!
         register-handler!
         unregister-handler!
         clear-handlers!)

(require ffi/unsafe
         "ctypes.rkt"
         "raw.rkt")

;; conn-id -> handler procedure
(define handlers (make-hash))
(define handlers-lock (make-semaphore 1))

(define dispatcher-thread #f)

(define logger (make-logger 'bezel))

(define (with-handlers-lock thunk)
  (dynamic-wind
    (lambda () (semaphore-wait handlers-lock))
    thunk
    (lambda () (semaphore-post handlers-lock))))

(define (ensure-dispatcher!)
  ;; Restart after shutdown (bezel-cleanup!) as well as on first use.
  (when (or (not dispatcher-thread)
            (thread-dead? dispatcher-thread))
    (set! dispatcher-thread (thread deliver-loop!))))

(define (register-handler! conn-id handler)
  (with-handlers-lock
   (lambda () (hash-set! handlers conn-id handler))))

(define (unregister-handler! conn-id)
  (with-handlers-lock
   (lambda () (hash-remove! handlers conn-id))))

(define (clear-handlers!)
  (with-handlers-lock
   (lambda () (hash-clear! handlers))))

(define (handler-ref conn-id)
  (with-handlers-lock
   (lambda () (hash-ref handlers conn-id #f))))

(define (variant->value v)
  (define tag (bezel-variant-vt v))
  (cond
    [(= tag +vt-int+) (bezel-variant-i v)]
    [(= tag +vt-double+) (bezel-variant-d v)]
    [(= tag +vt-bool+) (= 1 (bezel-variant-i v))]
    [(= tag +vt-string+)
     (define p (bezel-variant-s v))
     (begin0 (and p (bytes->string/utf-8 (cast p _pointer _bytes)))
       ;; String buffers delivered through the queue are owned by the
       ;; caller (us) — see bezel.h.
       (when p (bezel-free p)))]
    [(= tag +vt-object+) (bezel-variant-p v)]
    [else #f]))

(define (deliver! buf)
  (define id (bezel-signal-msg-conn-id buf))
  (cond
    ;; Negative ids are native lifecycle notices, never user-visible
    ;; connections. The absolute value is the retired connection id.
    [(negative? id)
     (unregister-handler! (- id))]
    [else
     (define args
       (for/list ([i (in-range (bezel-signal-msg-argc buf))])
         (variant->value (array-ref (bezel-signal-msg-argv buf) i))))
     (define handler (handler-ref id))
     (when handler
       (with-handlers ([(lambda (_e) #t)
                        (lambda (e)
                          ;; A user handler must never kill the dispatcher.
                          (log-message logger 'error
                                       (format "bezel: signal handler ~a raised: ~a"
                                               id
                                               (if (exn? e)
                                                   (exn-message e)
                                                   (format "~a" e)))
                                       #f))])
         (apply handler args)))]))

(define (deliver-loop!)
  (define buf (cast (malloc _bezel-signal-msg 'atomic)
                    _pointer
                    _bezel-signal-msg-pointer))
  (let loop ()
    ;; Non-blocking poll (timeout 0): a blocking foreign wait would
    ;; starve Racket CS's scheduler, so the yield happens Racket-side.
    (define r (bezel-next-signal 0 buf))
    (case r
      [(1) (deliver! buf) (loop)]
      [(-1) (void)]  ; shim shutdown
      [else (sleep 0.02) (loop)])))
