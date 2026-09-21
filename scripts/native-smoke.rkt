#lang racket/base

(require bezel)

(make-application #:name "Bezel native runtime smoke")
(define label (make-label "native-runtime-ok"))
(unless (equal? (widget-text label) "native-runtime-ok")
  (error 'native-smoke "unexpected label text: ~v" (widget-text label)))
(define win (make-window #:title "Bezel native runtime smoke" #:size '(160 80)))
(widget-show! win)
(process-events! 0)
(bezel-cleanup!)
(displayln "bezel native runtime smoke: OK")
