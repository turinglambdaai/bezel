#lang racket/base

;; This script is intentionally loaded without a static `(require bezel)` so
;; the hermetic flag is in place before bezel/private/lib is instantiated.
;; A green release smoke test therefore proves that the package-local runtime
;; works; it cannot fall back to a source build or a system libbezel.
(putenv "BEZEL_REQUIRE_PACKAGED_RUNTIME" "1")

(define make-application (dynamic-require 'bezel 'make-application))
(define make-label (dynamic-require 'bezel 'make-label))
(define widget-text (dynamic-require 'bezel 'widget-text))
(define make-window (dynamic-require 'bezel 'make-window))
(define widget-show! (dynamic-require 'bezel 'widget-show!))
(define process-events! (dynamic-require 'bezel 'process-events!))
(define bezel-cleanup! (dynamic-require 'bezel 'bezel-cleanup!))
(define selected-shim
  (dynamic-require 'bezel/private/lib 'loaded-bezel-library-path))

(make-application #:name "Bezel native runtime smoke")
(define label (make-label "native-runtime-ok"))
(unless (equal? (widget-text label) "native-runtime-ok")
  (error 'native-smoke "unexpected label text: ~v" (widget-text label)))
(define win (make-window #:title "Bezel native runtime smoke" #:size '(160 80)))
(widget-show! win)
(process-events! 0)
(bezel-cleanup!)
(displayln (format "bezel native runtime smoke: OK (~a)" selected-shim))
