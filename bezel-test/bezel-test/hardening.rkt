#lang racket/base

;; Commercial-hardening regression tests. These focus on failure paths,
;; ownership transitions, generated bindings, and native/binding
;; compatibility rather than only the happy-path widget coverage.

(require rackunit
         bezel
         (only-in bezel/private/lib
                  expected-bezel-abi-version
                  loaded-bezel-abi-version))

(putenv "QT_QPA_PLATFORM" "offscreen")

(define (wait-for pred [n 100])
  (let loop ([n n])
    (or (pred)
        (and (> n 0)
             (begin
               (sleep 0.02)
               (loop (sub1 n)))))))

;; Like wait-for, but also drains the GUI marshal queue. This is the
;; production pattern exercised by `run`, made explicit for a focused
;; cross-thread regression test.
(define (wait-for/pump pred [n 100])
  (let loop ([n n])
    (or (pred)
        (and (> n 0)
             (begin
               (process-events! 5)
               (sleep 0.01)
               (loop (sub1 n)))))))

(test-case "native ABI matches Racket bindings"
  (check-equal? loaded-bezel-abi-version expected-bezel-abi-version))

(make-application #:name "bezel-hardening-test")

(test-case "sentinel getters still surface wrong-widget errors"
  (define label (make-label "not a combo or list"))
  (check-exn exn:fail:bezel? (lambda () (combo-current-index label)))
  (check-exn exn:fail:bezel? (lambda () (list-current-row label)))
  (check-exn exn:fail:bezel? (lambda () (dial-value label))))

(test-case "generated bindings marshal calls from worker threads"
  (define dial (dial-new))
  (dial-set-range dial 0 200)
  (define result (box #f))
  (thread
   (lambda ()
     (dial-set-value dial 123)
     (set-box! result (dial-value dial))))
  (check-true (wait-for/pump (lambda () (equal? (unbox result) 123)))
              "generated bindings must marshal worker-thread Qt calls"))

(test-case "generated constructor rejects a dead parent"
  (define parent (make-widget))
  (bezel-delete! parent)
  (process-events! 10)
  (check-true (wait-for (lambda () (not (bezel-alive? parent)))))
  (check-exn exn:fail:bezel? (lambda () (dial-new parent))))

(test-case "disconnect validates the connection owner"
  (define a (make-button "a"))
  (define b (make-button "b"))
  (define hits (box 0))
  (define conn
    (connect! a "clicked()"
              (lambda _ (set-box! hits (add1 (unbox hits))))))

  ;; A wrong target must fail without silently unregistering the handler
  ;; that belongs to `a`.
  (check-exn exn:fail:bezel? (lambda () (disconnect! b conn)))
  (emit-test-signal! a "clicked()")
  (check-true (wait-for (lambda () (= 1 (unbox hits))))
              "failed disconnect must preserve the real handler")

  (disconnect! a conn)
  (emit-test-signal! a "clicked()")
  (sleep 0.1)
  (check-equal? (unbox hits) 1))

(test-case "test signal rejects unknown signatures"
  (define button (make-button "x"))
  (check-exn exn:fail:bezel?
             (lambda () (emit-test-signal! button "noSuchSignal(int)" (list 1)))))

(test-case "reparenting keeps the ownership diagnostic accurate"
  (define parent (make-widget))
  (define child (make-widget))
  (check-true (bezel-object-owned child))
  (object-set-parent! child parent)
  (check-false (bezel-object-owned child))
  (object-set-parent! child #f)
  (check-true (bezel-object-owned child)))

(test-case "pump arguments fail fast"
  (check-exn exn:fail:contract? (lambda () (process-events! -1)))
  (check-exn exn:fail:contract? (lambda () (run #:fps 0)))
  (check-exn exn:fail:contract? (lambda () (run #:fps +inf.0))))

(bezel-cleanup!)

(displayln "bezel-test hardening: all tests passed")
