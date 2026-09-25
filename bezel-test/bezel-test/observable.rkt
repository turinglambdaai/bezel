#lang racket/base

;; Multi-argument typed signals ((int,int) pairs) and the observable
;; data-binding layer. Requires only bezel/updates's pure helpers and
;; bezel/observable (no Qt shim), so this suite runs on any host; the
;; (int,int) signal test lives in desktop.rkt where a real table exists.

(require rackunit
         racket/list
         bezel/observable)

(define (wait-for pred [n 100])
  (let loop ([n n])
    (or (pred) (and (> n 0) (begin (sleep 0.02) (loop (sub1 n)))))))

;; ---- observables --------------------------------------------------------

(test-case "observe!: initial push + change notifications"
  (define o (make-observable 0))
  (define seen (box '()))
  (observe! o (lambda (v) (set-box! seen (cons v (unbox seen)))))
  (check-not-false (wait-for (lambda () (memv 0 (unbox seen)))) "initial value pushed")
  (set-observable! o 41)
  (check-not-false (wait-for (lambda () (memv 41 (unbox seen)))))
  (set-observable! o 42)
  (check-not-false (wait-for (lambda () (memv 42 (unbox seen))))))

(test-case "set-observable!: equal values skip watchers"
  (define o (make-observable "x"))
  (define hits (box 0))
  (observe! o (lambda (_) (set-box! hits (add1 (unbox hits)))))
  (set-observable! o "x")
  (set-observable! o "x")
  (sleep 0.1)
  (check-equal? (unbox hits) 1 "only the initial push ran")
  (check-false (set-observable! o "x") "returns #f when unchanged")
  (check-true (set-observable! o "y")))

(test-case "observe!: multiple watchers and unobserve!"
  (define o (make-observable 0))
  (define a (box #f)) (define b (box #f))
  (define tok (observe! o (lambda (v) (set-box! a v))))
  (observe! o (lambda (v) (set-box! b v)))
  (sleep 0.1)  ; let the initial pushes land before changing the value
  (set-observable! o 7)
  (check-not-false (wait-for (lambda () (and (unbox a) (unbox b) (= 7 (unbox a)) (= 7 (unbox b))))))
  (unobserve! o tok)
  (set-observable! o 9)
  (check-not-false (wait-for (lambda () (and (unbox b) (= 9 (unbox b))))))
  (sleep 0.1)
  (check-equal? (unbox a) 7 "removed watcher no longer fires"))

(test-case "observe!: a raising watcher does not kill the others"
  (define o (make-observable 0))
  (define ok (box #f))
  (observe! o (lambda (_) (raise-user-error 'boom)))
  (observe! o (lambda (v) (set-box! ok (= v 5))))
  (parameterize ([current-error-port (open-output-string)])
    (set-observable! o 5))
  (check-true (wait-for (lambda () (unbox ok)))))

(displayln "bezel-test/observable: all tests passed")
