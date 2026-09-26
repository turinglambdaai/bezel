#lang racket/base

;; Observables — a small data-binding layer for widget state.
;;
;;   (define count (make-observable 0))
;;   (observe! count (lambda (v) (widget-set-text! label (~a v))))
;;   (set-observable! count 41)             ; label still shows 41
;;   (set-observable! count 41)             ; no change: watchers skipped
;;   (set-observable! count 42)             ; label now shows 42
;;
;; Watchers run on their own Racket thread, like timer handlers: plain
;; computation inline, widget calls marshal to the GUI thread. A raising
;; watcher is reported to current-error-port and never removes itself or
;; kills other watchers.

(provide make-observable
         observable?
         observable-value
         set-observable!
         observe!
         unobserve!)

(struct observable ([value #:mutable] [watchers #:mutable] [lock #:mutable])
  #:transparent)

(define (make-observable initial)
  (observable initial '() (make-semaphore 1)))

(define (observable-assert! who o)
  (unless (observable? o)
    (raise-argument-error who "observable?" o)))

(define (with-observable-lock! o thunk)
  (semaphore-wait (observable-lock o))
  (dynamic-wind
      void
      thunk
      (lambda () (semaphore-post (observable-lock o)))))

;; Returns the watcher token; unobserve! accepts it back.
;; Fires once immediately so UI binds its initial value — synchronously:
;; an async initial push races the next set-observable!, and the old
;; value can land AFTER the new one, flipping the UI backwards.
(define (observe! o watcher)
  (observable-assert! 'observe! o)
  (unless (procedure? watcher)
    (raise-argument-error 'observe! "procedure?" watcher))
  (define token (gensym 'watcher))
  (with-observable-lock!
   o
   (lambda ()
     (set-observable-watchers! o (cons (cons token watcher)
                                       (observable-watchers o)))))
  (with-handlers ([exn? (lambda (e)
                          (eprintf "bezel: observable watcher raised: ~a\n"
                                   (exn-message e)))])
    (watcher (observable-value o)))
  token)

(define (unobserve! o token)
  (observable-assert! 'unobserve! o)
  (with-observable-lock!
   o
   (lambda ()
     (set-observable-watchers!
      o (filter (lambda (entry) (not (eq? (car entry) token)))
                (observable-watchers o)))))
  (void))

;; Returns #t when the value changed and watchers were scheduled.
(define (set-observable! o v)
  (observable-assert! 'set-observable! o)
  (define changed? #f)
  (define watchers
    (with-observable-lock!
     o
     (lambda ()
       (set! changed? (not (equal? (observable-value o) v)))
       (when changed? (set-observable-value! o v))
       (map cdr (observable-watchers o)))))
  (when changed?
    (for ([w (in-list watchers)]) (run-watcher! w v)))
  changed?)

(define (run-watcher! watcher v)
  ;; Own thread: a watcher that touches widgets marshals to the GUI
  ;; thread exactly like a timer handler.
  (thread
   (lambda ()
     (with-handlers ([exn? (lambda (e)
                             (eprintf "bezel: observable watcher raised: ~a\n"
                                      (exn-message e)))])
       (watcher v)))))
