#lang racket/base

;; Build an update-feed JSON for a local archive — used by CI to drive
;; the self-update end-to-end test. The archive URL is a real file://
;; URL (net/url round-trips it), so the packaged application exercises
;; the same download path as production.
;;
;;   racket scripts/make-feed.rkt <archive-path> <version> [sha1]

(require json
         file/sha1
         net/url
         racket/cmdline
         racket/file
         racket/path)

(define archive (make-parameter #f))
(define version (make-parameter #f))

(command-line
 #:args (archive-path feed-version)
 (archive (path->complete-path archive-path))
 (version feed-version))

(write-json
 (hasheq 'version (version)
         'url (url->string (path->url (archive)))
         'notes "CI self-update test"
         'sha1 (bytes->hex-string (sha1 (file->bytes (archive))))))
(newline)
