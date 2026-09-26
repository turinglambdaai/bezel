#lang racket/base

;; Packaging smoke entry: a minimal real Bezel application that quits by
;; itself. `raco bezel package` builds it into a standalone folder; the
;; clean-runner CI job then executes the packaged executable headlessly
;; and expects exit code 0 — proving the exe-relative native/ runtime
;; resolution works exactly as an end user's machine would see it.
;;
;; Environment knobs (used only by CI):
;;   BEZEL_SMOKE_FEED=<url>    run silent auto-update! against this feed
;;                             (exits and relaunches when an update applies)
;;   BEZEL_SMOKE_MARKER=<path> write the running version here, then quit

(require racket/file
         racket/string
         bezel)

(make-application #:name "bezel-demo")

(define (app-version)
  (with-handlers ([exn:fail? (lambda (_) "0.0.0")])
    (string-trim (file->string (build-path (packaged-app-root) "VERSION")))))

(define (feed) (getenv "BEZEL_SMOKE_FEED"))
(define (marker) (getenv "BEZEL_SMOKE_MARKER"))

(when (feed)
  ;; Silent self-update: on success this exits and the swapper
  ;; relaunches the new version; on "no update" it returns #f and we
  ;; fall through to the marker + quit path.
  (auto-update! #:feed (feed)))

(when (marker)
  (with-handlers ([exn:fail? void])
    (call-with-output-file (marker)
      #:exists 'replace
      (lambda (o) (display (app-version) o)))))

(define win (make-window #:title "Bezel packaged demo" #:size '(260 120)))
(define status (make-label "packaged runtime OK"))
(layout! win (vbox #:margins '(12 12 12 12) status))

;; One frame of the pump, then a clean exit.
(after! 300 (lambda () (quit! 0)))

(run win)
