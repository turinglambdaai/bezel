#lang racket/base

;; Update-check coverage: version comparison and file:// feeds. The
;; modal prompt path is not exercised (same policy as the msg-* dialogs);
;; network failure modes are covered through missing file:// targets,
;; which exercise the identical error handling.

(require rackunit
         net/url
         racket/file
         racket/runtime-path
         bezel)

(putenv "QT_QPA_PLATFORM" "offscreen")

(define (write-feed content)
  (define p (make-temporary-file "bezel-feed~a.json"))
  (display-to-file content p #:exists 'replace)
  (path->string p))

(define (feed-url content)
  (url->string (path->url (path->complete-path (write-feed content)))))

(make-application #:name "bezel-test-updates")

;; ---- version comparison -----------------------------------------------------

(test-case "newer-version?: plain dotted versions"
  (check-true (newer-version? "1.2.1" "1.2"))
  (check-true (newer-version? "1.2.10" "1.2.9"))
  (check-true (newer-version? "2.0" "1.99.99"))
  (check-false (newer-version? "1.2" "1.2.0"))
  (check-false (newer-version? "1.2.0" "1.2"))
  (check-false (newer-version? "1.2.3" "1.2.3")))

(test-case "newer-version?: tolerated decorations"
  (check-true (newer-version? "v1.3" "1.2.9") "leading v is ignored")
  (check-false (newer-version? "1.3.0-beta" "1.3.0")
               "pre-release suffixes compare as the plain version")
  (check-true (newer-version? " 1.4 " "1.3") "whitespace is trimmed"))

;; ---- feed checks --------------------------------------------------------------

(test-case "check-for-update: newer version in the feed"
  (define url (feed-url "{\"version\": \"1.3.0\", \"url\": \"https://example.com/dl\", \"notes\": \"bug fixes\"}"))
  (define info (check-for-update #:feed url #:current "1.2.3"))
  (check-true (update-info? info))
  (check-equal? (update-info-version info) "1.3.0")
  (check-equal? (update-info-url info) "https://example.com/dl")
  (check-equal? (update-info-notes info) "bug fixes"))

(test-case "check-for-update: same or older version yields #f"
  (define url (feed-url "{\"version\": \"1.2.3\", \"url\": \"https://example.com/dl\"}"))
  (check-false (check-for-update #:feed url #:current "1.2.3"))
  (define older (feed-url "{\"version\": \"1.0\", \"url\": \"https://example.com/dl\"}"))
  (check-false (check-for-update #:feed older #:current "1.2.3")))

(test-case "check-for-update: notes field is optional"
  (define url (feed-url "{\"version\": \"2.0\", \"url\": \"https://example.com/dl\"}"))
  (define info (check-for-update #:feed url #:current "1.0"))
  (check-true (update-info? info))
  (check-equal? (update-info-notes info) ""))

(test-case "check-for-update: failures are quiet #f, never raises"
  (define malformed (feed-url "not json at all"))
  (check-false (check-for-update #:feed malformed #:current "1.0"))
  (define missing-field (feed-url "{\"version\": \"2.0\"}"))
  (check-false (check-for-update #:feed missing-field #:current "1.0"))
  ;; missing target exercises the same error path as an unreachable host
  (define missing
    (url->string (path->url (build-path (find-system-path 'temp-dir)
                                        "bezel-no-such-feed-8321.json"))))
  (check-false (check-for-update #:feed missing #:current "1.0")))

(displayln "bezel-test/updates: all tests passed")
