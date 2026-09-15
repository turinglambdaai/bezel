#lang racket/base

;; GUI-thread marshaling — the Racket side of the threading contract.
;;
;; The C ABI never blocks on a cross-thread handoff: a raw foreign wait
;; freezes Racket CS's cooperatively scheduled threads (which can migrate
;; between OS threads), deadlocking the pump. Instead, a bezel call made
;; from a non-GUI thread enqueues a thunk and waits on a Racket
;; semaphore — cooperative, so the scheduler keeps running, the main
;; thread's pump keeps draining, and the call completes. On the GUI
;; thread itself, calls run inline.
;;
;; raw.rkt routes every binding through `gui` (except the few that must
;; not marshal: the signal poll, error query, free). The pump — run and
;; process-events! — drains the queue once per iteration via drain-gui!.

(provide gui
         drain-gui!)

(require ffi/unsafe
         racket/mpair
         "lib.rkt")

;; 1 when the calling OS thread is the Qt GUI thread (no marshaling
;; needed). Bound directly from the shim to avoid a raw.rkt cycle.
(define bezel-on-gui-thread*
  (get-ffi-obj 'bezel_on_gui_thread bezel-lib (_fun -> _int)
               (lambda () (error 'bezel "shim is missing bezel_on_gui_thread"))))

(struct marshal-task (thunk done-sem result-box error-box) #:mutable)

;; Direct shim bindings (no marshaling — these are the plumbing).
(define bezel-last-error*
  (get-ffi-obj 'bezel_last_error bezel-lib (_fun -> _string/utf-8)
               (lambda () (error 'bezel "shim is missing bezel_last_error"))))
(define bezel-set-last-error*
  (get-ffi-obj 'bezel_set_last_error bezel-lib (_fun _string/utf-8 -> _void)
               (lambda () (error 'bezel "shim is missing bezel_set_last_error"))))

;; FIFO of marshal-tasks waiting for the GUI thread.
(define head '())
(define tail-cell (box #f))

(define (enqueue! task)
  (define cell (mcons task '()))
  (if (null? head)
      (begin (set! head cell)
             (set-box! tail-cell cell))
      (begin (set-mcdr! (unbox tail-cell) cell)
             (set-box! tail-cell cell))))

;; Run `thunk` on the GUI thread, returning its value. A thunk that
;; raises re-raises on the caller. Safe from any thread.
(define (gui thunk)
  (if (= 1 (bezel-on-gui-thread*))
      (thunk)
      (let* ([err-box (box #f)]
             [task (marshal-task #f (make-semaphore) (box #f) err-box)])
        ;; The shim's error slot is thread-local: after the thunk runs on
        ;; the GUI thread, carry its error string back and replay it on
        ;; the calling thread so `ok!` & co. see the real message.
        (set-marshal-task-thunk!
         task
         (lambda ()
           (begin0 (thunk)
             (set-box! err-box (bezel-last-error*)))))
        (enqueue! task)
        (let loop ()
          (unless (sync/timeout 0.005 (marshal-task-done-sem task))
            (loop)))
        (define err (unbox err-box))
        (when (and (string? err) (not (equal? "" err)))
          (bezel-set-last-error* err))
        (define result (unbox (marshal-task-result-box task)))
        (if (exn? result)
            (raise result)
            result))))

;; Run every pending queued task. Called from the pump on the main
;; (GUI) thread. Never call from other threads.
(define (drain-gui!)
  (let next ()
    (unless (null? head)
      (define cell head)
      (set! head (mcdr cell))
      (when (null? head) (set-box! tail-cell #f))
      (define task (mcar cell))
      (define result
        (with-handlers ([(lambda (_e) #t) (lambda (e) e)])
          ((marshal-task-thunk task))))
      (set-box! (marshal-task-result-box task) result)
      (semaphore-post (marshal-task-done-sem task))
      (next))))
