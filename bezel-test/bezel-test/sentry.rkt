#lang racket/base

;; Sentry reporter coverage against a throwaway local HTTP server —
;; hermetic on every machine. Requires only bezel/sentry (no Qt shim),
;; so this suite also runs on hosts without libbezel.

(require rackunit
         json
         racket/string
         racket/tcp
         bezel/sentry)

;; Accept exactly one HTTP request; capture its headers and JSON body.
(define (start-fake-sentry!)
  (define listener (tcp-listen 0 1 #t "127.0.0.1"))
  (define port
    (let-values ([(_local-host local-port _remote-host _remote-port)
                  (tcp-addresses listener #t)])
      local-port))
  (define received (box #f))
  (thread
   (lambda ()
     (with-handlers ([exn:fail? void])
       (define-values (in out) (tcp-accept listener))
       (define head-lines
         (let loop ()
           (define l (read-line in))
           (if (or (eof-object? l)
                   (string=? (string-trim l) ""))
               '()
               (cons (string-trim l) (loop)))))
       (define content-length
         (for/or ([l (in-list head-lines)])
           (define m (regexp-match #rx"(?i:^Content-Length: *([0-9]+))" l))
           (and m (string->number (cadr m)))))
       (define body (and content-length (read-bytes content-length in)))
       (set-box! received (cons head-lines body))
       (display "HTTP/1.1 200 OK\r\nContent-Length: 0\r\n\r\n" out)
       (flush-output out)
       (tcp-close listener))))
  (values port received))

(define (wait-for pred [n 100])
  (let loop ([n n])
    (or (pred) (and (> n 0) (begin (sleep 0.02) (loop (sub1 n)))))))

;; ---- DSN parsing --------------------------------------------------------------

(test-case "dsn->endpoint: standard shapes"
  (define-values (url key)
    (dsn->endpoint "https://abc123@o42.ingest.sentry.io/5555"))
  (check-equal? url "https://o42.ingest.sentry.io/api/5555/store/")
  (check-equal? key "abc123")
  (define-values (u2 k2) (dsn->endpoint "http://pub@127.0.0.1:9999/7"))
  (check-equal? u2 "http://127.0.0.1:9999/api/7/store/")
  (check-equal? k2 "pub")
  (check-exn exn:fail:contract? (lambda () (dsn->endpoint "not-a-dsn"))))

;; ---- event construction -----------------------------------------------------------

(test-case "exn->sentry-event: shape"
  (define e (with-handlers ([exn:fail? values]) (raise-argument-error 'demo "number?" "x")))
  (define ev (exn->sentry-event e))
  (check-true (string? (hash-ref ev 'event_id)))
  (check-not-false (regexp-match #px"^[0-9a-f]{32}$" (hash-ref ev 'event_id)))
  (check-equal? (hash-ref ev 'level) "error")
  (check-equal? (hash-ref ev 'platform) "racket")
  (define exc (hash-ref ev 'exception))
  (check-true (non-empty-string? (hash-ref exc 'value)))
  (check-true (list? (hash-ref (hash-ref exc 'stacktrace) 'frames))))

(test-case "message->sentry-event: shape"
  (define ev (message->sentry-event "hello" #:level 'warning))
  (check-equal? (hash-ref ev 'message) "hello")
  (check-equal? (hash-ref ev 'level) "warning"))

;; ---- sending (against the fake server) ----------------------------------------------

(test-case "send-sentry-event!: real POST with auth header and JSON body"
  (define-values (port received) (start-fake-sentry!))
  (define dsn (format "http://pubkey@127.0.0.1:~a/42" port))
  (define ok? (send-sentry-event! dsn (message->sentry-event "from the test")))
  (check-true ok? "local POST should succeed")
  (check-not-false (wait-for (lambda () (unbox received))) "server should see the request")
  (define head (car (unbox received)))
  (define body (read-json (open-input-bytes (cdr (unbox received)))))
  (check-not-false (member "POST /api/42/store/ HTTP/1.1" head)
                    (format "request line goes to the store endpoint: ~a" (car head)))
  (define auth
    (for/or ([l (in-list head)])
      (and (regexp-match #rx"(?i:^X-Sentry-Auth:)" l) l)))
  (check-not-false (and auth (regexp-match #rx"sentry_key=pubkey" auth))
                    "auth header carries the public key")
  (check-equal? (hash-ref body 'message) "from the test")
  (check-true (string? (hash-ref body 'event_id))))

(test-case "send-sentry-event!: unreachable server is a quiet #f"
  ;; port 1 has no listener on test machines (binding it needs privileges)
  (check-false (send-sentry-event! "http://k@127.0.0.1:1/1"
                                   (message->sentry-event "x"))))

;; ---- installed reporter ---------------------------------------------------------------

(test-case "install-sentry-reporter!: uncaught errors reach the server"
  (define-values (port received) (start-fake-sentry!))
  (define dsn (format "http://pubkey@127.0.0.1:~a/42" port))
  (install-sentry-reporter! dsn #:release "9.9.9-test")
  (define handler (error-display-handler))
  (define e (with-handlers ([exn:fail? values]) (raise-argument-error 'demo-reporter "number?" "x")))
  ;; Invoke like the runtime would; the original handler's stderr output
  ;; is swallowed so the test log stays clean.
  (parameterize ([current-error-port (open-output-string)])
    (handler (exn-message e) e))
  (check-not-false (wait-for (lambda () (unbox received))))
  (define body (read-json (open-input-bytes (cdr (unbox received)))))
  (check-equal? (hash-ref body 'release) "9.9.9-test")
  (check-true (hash-has-key? body 'exception))
  (check-true (string-contains? (hash-ref (hash-ref body 'exception) 'value)
                                "number?")))

(displayln "bezel-test/sentry: all tests passed")
