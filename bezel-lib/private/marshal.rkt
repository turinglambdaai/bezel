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

(struct marshal-task (thunk done-sem result-box))

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
      (let ([task (marshal-task thunk (make-semaphore) (box #f))])
        (enqueue! task)
        (let loop ()
          (unless (sync/timeout 0.005 (marshal-task-done-sem task))
            (loop)))
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
