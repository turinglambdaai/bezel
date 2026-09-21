#lang racket/base

;; Commercial-hardening regression tests. These focus on failure paths,
;; ownership transitions, and native/binding compatibility rather than
;; the happy-path widget coverage in main.rkt.

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

(test-case "native ABI matches Racket bindings"
  (check-equal? loaded-bezel-abi-version expected-bezel-abi-version))

(make-application #:name "bezel-hardening-test")

(test-case "sentinel getters still surface wrong-widget errors"
  (define label (make-label "not a combo or list"))
  (check-exn exn:fail:bezel? (lambda () (combo-current-index label)))
  (check-exn exn:fail:bezel? (lambda () (list-current-row label))))

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
