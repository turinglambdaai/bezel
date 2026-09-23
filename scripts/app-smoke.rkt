#lang racket/base

;; Packaging smoke entry: a minimal real Bezel application that quits by
;; itself. `raco bezel package` builds it into a standalone folder; the
;; clean-runner CI job then executes the packaged executable headlessly
;; and expects exit code 0 — proving the exe-relative native/ runtime
;; resolution works exactly as an end user's machine would see it.

(require bezel)

(make-application #:name "bezel-demo")

(define win (make-window #:title "Bezel packaged demo" #:size '(260 120)))
(define status (make-label "packaged runtime OK"))
(layout! win (vbox #:margins '(12 12 12 12) status))

;; One frame of the pump, then a clean exit.
(after! 300 (lambda () (quit! 0)))

(run win)
