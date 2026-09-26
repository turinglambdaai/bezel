#lang racket/base

;; Timer lifecycle coverage: registration, per-timer stops, and the
;; teardown sweep. Pure Racket — no Qt shim needed, so this suite runs
;; on any host.

(require rackunit
         bezel/timers)

(define (wait-for pred [n 100])
  (let loop ([n n])
    (or (pred) (and (> n 0) (begin (sleep 0.02) (loop (sub1 n)))))))

(test-case "after! fires once and reports stopped"
  (define fired (box #f))
  (define t (after! 40 (lambda () (set-box! fired #t))))
  (check-true (bezel-timer-running? t))
  (check-not-false (wait-for (lambda () (unbox fired))))
  (check-false (bezel-timer-running? t) "one-shot retires itself"))

(test-case "stop-timer! prevents later firings"
  (define n (box 0))
  (define t (every! 40 (lambda () (set-box! n (add1 (unbox n))))))
  (check-not-false (wait-for (lambda () (> (unbox n) 0))))
  (stop-timer! t)
  (define at-stop (unbox n))
  (sleep 0.15)
  (check-equal? (unbox n) at-stop "no ticks after the stop")
  (check-false (bezel-timer-running? t)))

(test-case "stop-all-timers! sweeps every pending timer"
  (define a (box 0))
  (define b (box 0))
  (define t1 (every! 30 (lambda () (set-box! a (add1 (unbox a))))))
  (define t2 (every! 50 (lambda () (set-box! b (add1 (unbox b))))))
  (define t3 (after! 5000 void))  ; long pending one-shot
  (sleep 0.12)
  (stop-all-timers!)
  (check-false (bezel-timer-running? t1))
  (check-false (bezel-timer-running? t2))
  (check-false (bezel-timer-running? t3) "pending after! timers are swept too")
  (define a-at (unbox a))
  (define b-at (unbox b))
  (sleep 0.15)
  (check-equal? (unbox a) a-at)
  (check-equal? (unbox b) b-at))

(displayln "bezel-test/timers: all tests passed")
