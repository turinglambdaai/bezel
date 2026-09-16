#lang racket/base

;; GUI-thread marshaling — the Racket side of the threading contract.
;;
;; The C ABI never blocks on a cross-thread handoff: a raw foreign wait
;; freezes Racket CS's cooperatively scheduled threads (which can migrate
;; between OS threads), deadlocking the pump. Instead, a bezel call made
;; from a non-GUI thread enqueues a thunk and waits on a Racket
;; semaphore — cooperative, so the scheduler keeps running, the main
;; thread's pump keeps draining, and the call completes. On the main
;; thread itself, calls run inline.
;;
;; raw.rkt routes every binding through `gui` (except the few that must
;; not marshal: the signal poll, error pair, free). The pump — run and
;; process-events! — drains the queue once per iteration via drain-gui!.

(provide gui
         drain-gui!)

(require ffi/unsafe
         racket/mpair
         "lib.rkt")

(define marshal-debug? (getenv "BEZEL_MARSHAL_DEBUG"))

(define (trace fmt . args)
  (when marshal-debug? (apply eprintf fmt args)))

;; The GUI-thread decision: only the Racket main thread (the one that
;; loads Bezel and runs the pump) executes Qt calls inline. Every other
;; Racket thread marshals, always. Asking Qt "is this the GUI thread"
;; is unsound here: Racket CS threads can multiplex onto the main OS
;; thread, so a worker thread can *look* like the GUI thread while
;; another Racket thread is mid-foreign-call on that same OS thread —
;; an inline Qt call then wedges the OS thread and deadlocks the place.
(define gui-main-thread (current-thread))

(struct marshal-task (thunk done-sem result-box error-box))

;; Direct shim bindings (no marshaling — these are the plumbing).
(define bezel-last-error*
  (get-ffi-obj 'bezel_last_error bezel-lib (_fun -> _string/utf-8)
               (lambda () (error 'bezel "shim is missing bezel_last_error"))))
(define bezel-set-last-error*
  (get-ffi-obj 'bezel_set_last_error bezel-lib (_fun _string/utf-8 -> _void)
               (lambda () (error 'bezel "shim is missing bezel_set_last_error"))))

;; ---- task queue ----------------------------------------------------------
;;
;; FIFO of marshal-tasks waiting for the GUI thread. Callers enqueue
;; from any thread while the pump drains on the main thread — every
;; queue access holds queue-lock (a binary semaphore as mutex; Racket
;; pair mutation is not thread-safe).

(define queue-lock (make-semaphore 1))
(define head '())
(define tail-cell (box #f))

(define (with-lock thunk)
  (dynamic-wind
      (lambda () (semaphore-wait queue-lock))
      thunk
      (lambda () (semaphore-post queue-lock))))

(define (enqueue! task)
  (with-lock
   (lambda ()
     (define cell (mcons task '()))
     (cond [(null? head)
            (set! head cell)
            (set-box! tail-cell cell)]
           [else
            (set-mcdr! (unbox tail-cell) cell)
            (set-box! tail-cell cell)]))))

(define (dequeue!)
  (with-lock
   (lambda ()
     (and (not (null? head))
          (let ([cell head])
            (set! head (mcdr cell))
            (when (null? head) (set-box! tail-cell #f))
            (mcar cell))))))

;; ---- handoff ---------------------------------------------------------------

;; Copy `err` into the calling thread's shim error slot. The shim's
;; error storage is thread-local, so a marshaled call that failed on
;; the GUI thread must carry its message back or the caller's `ok!`
;; would report "unknown error".
(define (replay-error! err)
  (when (and (string? err) (not (equal? "" err)))
    (bezel-set-last-error* err)))

;; Wait until `task` completes (its semaphore is posted once, so a
;; missed sync still succeeds on the next poll).
(define (await-task task)
  (let loop ([polls 0])
    (unless (sync/timeout 0.005 (marshal-task-done-sem task))
      (trace "[gui] still waiting (~a)" polls)
      (loop (add1 polls)))))

;; Run `thunk` on the main thread, returning its value. A thunk that
;; raises re-raises on the caller. Safe from any thread.
(define (gui thunk)
  (cond
    [(eq? (current-thread) gui-main-thread)
     (trace "[gui] inline on main thread")
     (thunk)]
    [else
     (define err-box (box #f))
     (define (task-thunk)
       (begin0 (thunk) (set-box! err-box (bezel-last-error*))))
     (define task (marshal-task task-thunk (make-semaphore) (box #f) err-box))
     (enqueue! task)
     (trace "[gui] enqueued, waiting")
     (await-task task)
     (replay-error! (unbox err-box))
     (define result (unbox (marshal-task-result-box task)))
     (if (exn? result) (raise result) result)]))

;; Run every pending queued task. Called from the pump on the main
;; thread. Thunks run OUTSIDE the lock (a thunk may block on its own
;; handshake while other threads keep enqueueing) — dequeue one at a
;; time, each under the lock.
(define (drain-gui!)
  (let next ()
    (define task (dequeue!))
    (when task
      (trace "[drain] running one task")
      (define result
        (with-handlers ([(lambda (_e) #t) (lambda (e) e)])
          ((marshal-task-thunk task))))
      (set-box! (marshal-task-result-box task) result)
      (semaphore-post (marshal-task-done-sem task))
      (next))))
