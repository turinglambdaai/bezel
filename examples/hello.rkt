#lang racket/base

;; Minimal Bezel app — 12 lines. Run: racket examples/hello.rkt

(require bezel)

(define n (box 0))
(define count (make-label "Clicked 0 times"))
(define btn (make-button "Click me"))
(connect! btn "clicked()" (lambda _
  (set-box! n (add1 (unbox n)))
  (widget-set-text! count (format "Clicked ~a times" (unbox n)))))

(define win (make-window #:title "Hello Bezel" #:size '(320 140)))
(layout! win (vbox #:margins '(16 16 16 16) count btn))
(run win)
