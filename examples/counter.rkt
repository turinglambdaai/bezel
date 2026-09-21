#lang racket/base

;; Counter with Qt Style Sheets (QSS) — the styling story racket/gui
;; never had. Run: racket examples/counter.rkt

(require bezel)

(make-application #:name "Bezel Counter")

(define stylesheet
  (string-append
   "QWidget { background: #F4F3EE; font-size: 15px; }"
   "QLabel#count { font-size: 42px; font-weight: 600; color: #1F1E1B; }"
   "QPushButton { background: #C15F3C; color: white; border: none;"
   "              border-radius: 8px; padding: 10px 22px; font-weight: 600; }"
   "QPushButton:hover { background: #A84F30; }"
   "QPushButton:pressed { background: #8F4228; }"))

(define n (box 0))
(define count (make-label "0"))
(set-qt-object-name! count "count")

(define plus (make-button "+ 1"))
(define reset (make-button "reset"))
(connect! plus "clicked()" (lambda _
  (set-box! n (add1 (unbox n)))
  (widget-set-text! count (number->string (unbox n)))))
(connect! reset "clicked()" (lambda _
  (set-box! n 0)
  (widget-set-text! count "0")))

(define win (make-window #:title "Counter — Bezel" #:size '(300 200)
                         #:stylesheet stylesheet))
(layout! win (vbox #:margins '(24 24 24 24)
                   count
                   (hbox plus reset)
                   stretch))
(run win)
