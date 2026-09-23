#lang racket/base

;; Best-effort application update checks.
;;
;;   (after! 1000 (lambda ()
;;     (check-and-prompt-update!
;;      #:feed "https://example.com/myapp-updates.json"
;;      #:current "1.2.3"
;;      #:parent win)))
;;
;; The feed is one static JSON file the application author hosts anywhere:
;;
;;   {"version": "1.3.0",
;;    "url": "https://github.com/me/myapp/releases/latest",
;;    "notes": "Optional release notes"}
;;
;; Check semantics (deliberately quiet — an update check must never take
;; the application down): unreachable feeds, timeouts, malformed JSON, and
;; missing fields all return #f rather than raising. Pre-release suffixes
;; in versions are ignored ("1.3.0-beta" compares as "1.3.0"), and a
;; leading v/V is tolerated.
;;
;; `check-and-prompt-update!` asks the user through the native modal
;; question dialog and opens the release page in the system browser on
;; confirmation. It does not download or replace anything — shipping the
;; update itself remains the distribution channel's job (see
;; docs/APP_PACKAGING.md).

(provide (struct-out update-info)
         newer-version?
         check-for-update
         check-and-prompt-update!)

(require json
         net/sendurl
         net/url
         racket/list
         racket/port
         racket/string
         "dialogs.rkt")

(struct update-info (version url notes) #:transparent)

;; Plainly-dotted versions: numeric elements only, padding with zeros so
;; "1.2" < "1.2.1". Non-numeric parts contribute 0, which makes
;; "1.3.0-beta" equal "1.3.0" — pre-release channels are out of scope.
(define (version->numbers v)
  (for/list ([part (in-list (string-split
                             (regexp-replace #px"^[vV]+" (string-trim v) "")
                             "."))])
    (define digits (regexp-match #px"^[0-9]+" part))
    (if digits (string->number (car digits)) 0)))

(define (newer-version? candidate current)
  (define a (version->numbers candidate))
  (define b (version->numbers current))
  (define n (max (length a) (length b)))
  (let loop ([a (append a (make-list (- n (length a)) 0))]
             [b (append b (make-list (- n (length b)) 0))])
    (cond [(> (car a) (car b)) #t]
          [(< (car a) (car b)) #f]
          [(null? (cdr a)) #f]     ; equal lists are not "newer"
          [else (loop (cdr a) (cdr b))])))

;; Parse the feed document; #f when it is not the expected shape.
(define (parse-feed j)
  (and (hash? j)
       (let ([v (hash-ref j 'version #f)]
             [u (hash-ref j 'url #f)])
         (and (string? v) (non-empty-string? v)
              (string? u) (non-empty-string? u)
              (update-info v u
                           (let ([n (hash-ref j 'notes #f)])
                             (if (string? n) n "")))))))

;; Fetch + parse inside a dedicated custodian so a timeout can close the
;; connection cleanly instead of leaking it to GC.
(define (fetch-update-info feed-url timeout-ms)
  (define result-ch (make-channel))
  (define cust (make-custodian))
  (parameterize ([current-custodian cust])
    (thread
     (lambda ()
       (channel-put
        result-ch
        (with-handlers ([exn:fail? (lambda (e) #f)])
          (parse-feed (call/input-url (string->url feed-url)
                                      get-pure-port
                                      read-json)))))))
  (begin0 (sync/timeout (/ timeout-ms 1000.0) result-ch)
    (custodian-shutdown-all cust)))

;; Blocking, best-effort: returns update-info only when the feed reports
;; a version newer than `current`; #f for "no update" and for every
;; failure mode (see module note). Call from a timer or background
;; thread so the request never stalls startup.
(define (check-for-update #:feed feed-url
                          #:current current-version
                          #:timeout-ms [timeout-ms 5000])
  (define info (fetch-update-info feed-url timeout-ms))
  (and info
       (newer-version? (update-info-version info) current-version)
       info))

;; Check, ask, and (on confirmation) open the release page in the system
;; browser. Returns the update-info when a newer version exists, #f
;; otherwise; note the modal dialog runs on the GUI thread like every
;; msg-* call — invoke this from the main thread, a handler, or a timer.
(define (check-and-prompt-update! #:feed feed-url
                                  #:current current-version
                                  #:parent [parent #f]
                                  #:timeout-ms [timeout-ms 5000])
  (define info (check-for-update #:feed feed-url
                                 #:current current-version
                                 #:timeout-ms timeout-ms))
  (and info
       (let ([open? (msg-question
                     (string-append
                      (format "Version ~a is available."
                              (update-info-version info))
                      (let ([n (update-info-notes info)])
                        (if (non-empty-string? n)
                            (string-append "\n\n" n)
                            "")))
                     #:parent parent
                     #:title "Update available")])
         (when open? (send-url (update-info-url info)))
         info)))
