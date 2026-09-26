#lang racket/base

;; Error reporting to a Sentry-compatible server, from plain Racket.
;;
;;   (install-sentry-reporter! "https://<key>@o<org>.ingest.sentry.io/<project>"
;;                             #:release "1.2.3")
;;
;; The reporter hooks error-display-handler: every uncaught exception the
;; runtime prints is also queued to Sentry on a background thread. Sends
;; are best-effort — a dead DSN or an offline machine never disturbs the
;; application. This covers Racket-level exceptions; native crashes
;; inside Qt/libbezel bypass the Racket runtime and are out of scope.
;;
;; Manual reporting:
;;
;;   (report-error! some-exn)              ; or
;;   (report-message! "cache invalidated")
;;
;; This module deliberately requires nothing from the Qt side, so it can
;; be used (and tested) headlessly and even in non-GUI tools.

(provide exn->sentry-event
         message->sentry-event
         dsn->endpoint
         send-sentry-event!
         install-sentry-reporter!
         report-error!
         report-message!)

(require json
         net/url
         racket/date
         racket/format
         racket/list
         racket/match
         racket/port
         racket/string
         "version.rkt")

;; ---- DSN parsing --------------------------------------------------------------

;; "https://key@host[:port]/project" -> "https://host[:port]/api/project/store/"
(define (dsn->endpoint dsn)
  (define m (regexp-match #px"^([a-z]+)://([^@]+)@([^/]+)(?:/(.+))?$" dsn))
  (unless m (raise-argument-error 'dsn->endpoint "sentry DSN string" dsn))
  (define scheme (list-ref m 1))
  (define key (list-ref m 2))
  (define host (list-ref m 3))
  (define project (or (list-ref m 4) ""))
  (values (format "~a://~a/api/~a/store/" scheme host project) key))

(define (dsn-parts dsn)
  (define-values (endpoint key) (dsn->endpoint dsn))
  (list endpoint key))

;; ---- event construction ---------------------------------------------------------

(define (random-hex-id)
  (string-join (for/list ([_ (in-range 16)]) (~r (random 256) #:base 16 #:min-width 2 #:pad-string "0")) ""))

(define (iso-timestamp)
  (parameterize ([date-display-format 'iso-8601])
    (date->string (current-date) #t)))

(define (exn-type-name e)
  (cond [(symbol? (object-name e)) (symbol->string (object-name e))]
        [else "error"]))

;; Continuation marks -> Sentry frames (innermost first, capped).
(define (marks->frames marks)
  (define ctx (continuation-mark-set->context marks))
  (for/list ([frame (in-list (take (reverse ctx) (min 50 (length ctx))))])
    (match frame
      [(list src (? number? line) _ ...)
       (hasheq 'filename (~a (or src "<unknown>")) 'lineno line)]
      [_ (hasheq 'filename "<unknown>")])))

(define (base-event level)
  (hasheq 'event_id (random-hex-id)
          'timestamp (iso-timestamp)
          'platform "racket"
          'level (~a level)
          'release (installed-release)))

(define (exn->sentry-event e)
  (hash-set* (base-event "error")
               'exception
               (hasheq 'type (exn-type-name e)
                       'value (exn-message e)
                       'stacktrace (hasheq 'frames (marks->frames (exn-continuation-marks e))))
               'extra
               (hasheq 'racket_version (version))))

(define (message->sentry-event text #:level [level 'info])
  (hash-set* (base-event level)
               'message text))

;; ---- sending ----------------------------------------------------------------------

(define client-name (format "bezel/~a" bezel-version))

;; POST one event to the store endpoint. Returns #t on a completed
;; request, #f for every failure (network, HTTP, serialization).
(define (send-sentry-event! dsn event)
  (with-handlers ([exn:fail? (lambda (e) #f)])
    (match-define (list endpoint key) (dsn-parts dsn))
    (define body (jsexpr->bytes event))
    (define p
      (post-pure-port (string->url endpoint) body
                      (list "Content-Type: application/json"
                            (format "X-Sentry-Auth: Sentry sentry_version=7, sentry_client=~a, sentry_key=~a"
                                    client-name key))))
    (begin0 #t
      (close-input-port p))))

;; ---- reporter installation ----------------------------------------------------------

(define installed-dsn #f)
(define installed-release-value "unknown")

(define (installed-release) installed-release-value)

(define (queue-event! event)
  ;; Background, best-effort, never surfaces an error into the app.
  (thread (lambda ()
            (with-handlers ([exn:fail? void])
              (when installed-dsn (send-sentry-event! installed-dsn event))))))

(define (install-sentry-reporter! dsn #:release [release "unknown"])
  (unless (string? dsn)
    (raise-argument-error 'install-sentry-reporter! "sentry DSN string" dsn))
  ;; Fail fast on a malformed DSN rather than silently at first error.
  (dsn->endpoint dsn)
  (set! installed-dsn dsn)
  (set! installed-release-value release)
  (define original-handler (error-display-handler))
  (error-display-handler
   (lambda (message exn)
     (queue-event! (if (exn? exn) (exn->sentry-event exn) (message->sentry-event message)))
     (original-handler message exn)))
  (void))

;; Manual reporting helpers (use the installed DSN).
(define (report-error! e)
  (unless (exn? e) (raise-argument-error 'report-error! "exn?" e))
  (unless installed-dsn
    (error 'report-error! "no reporter installed — call install-sentry-reporter! first"))
  (queue-event! (exn->sentry-event e)))

(define (report-message! text #:level [level 'info])
  (unless (string? text) (raise-argument-error 'report-message! "string?" text))
  (unless installed-dsn
    (error 'report-message! "no reporter installed — call install-sentry-reporter! first"))
  (queue-event! (message->sentry-event text #:level level)))
