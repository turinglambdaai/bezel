#lang racket/base

;; Generates docs/showcase.png — a real Qt-rendered screenshot of the
;; counter example, produced headlessly via the offscreen platform
;; plugin. This is Bezel's own agent-friendly verification turned on
;; itself: the README image is built by CI, by `make showcase`, or by
;;
;;   QT_QPA_PLATFORM=offscreen racket scripts/showcase.rkt

(require bezel
         racket/file
         racket/string)

(putenv "QT_QPA_PLATFORM" "offscreen")

(module+ main
  (make-application #:name "Bezel Showcase")

  (define stylesheet
    (string-append
     "QWidget { background: #F4F3EE; font-size: 15px; }"
     "QLabel { color: #1F1E1B; }"
     "QLabel#title { font-size: 34px; font-weight: 700; }"
     "QLabel#subtitle { font-size: 15px; color: #6B6862; }"
     "QLabel#count { font-size: 64px; font-weight: 700; color: #C15F3C; }"
     "QPushButton { background: #C15F3C; color: white; border: none;"
     "              border-radius: 10px; padding: 12px 26px; font-size: 17px; font-weight: 600; }"
     "QPushButton:hover { background: #A84F30; }"
     "QLineEdit { background: white; border: 1px solid #D9D6CE;"
     "            border-radius: 8px; padding: 8px 12px; font-size: 15px; }"
     "QListWidget { background: white; border: 1px solid #D9D6CE; border-radius: 8px; }"
     "QCheckBox { spacing: 8px; }"))

  (define n (box 3))
  (define title (make-label "Bezel"))
  (set-qt-object-name! title "title")
  (define subtitle (make-label "Native Qt 6 widgets, written in Racket"))
  (set-qt-object-name! subtitle "subtitle")
  (define count (make-label (number->string (unbox n))))
  (set-qt-object-name! count "count")
  (define plus (make-button "+ 1"))
  (connect! plus "clicked()" (lambda _
    (set-box! n (add1 (unbox n)))
    (widget-set-text! count (number->string (unbox n)))))
  (define name-field (make-line-edit "Ada Lovelace"))
  (define languages (make-list-widget))
  (list-add! languages "Racket")
  (list-add! languages "Qt 6")
  (list-add! languages "QSS styling")
  (list-select! languages 0)
  (define shipped (make-checkbox "Ships to macOS, Windows, Linux"))
  (set-widget-checked! shipped #t)

  (define win (make-window #:title "Bezel — Qt 6 for Racket"
                           #:size '(760 480)
                           #:stylesheet stylesheet))
  (layout! win
           (vbox #:spacing 14
                 #:margins '(48 40 48 40)
                 title
                 subtitle
                 (hbox #:spacing 24
                       (vbox count
                             (hbox plus
                                   (make-button "reset"))
                             stretch)
                       (vbox (make-label "Your name")
                             name-field
                             stretch)
                       (vbox languages
                             shipped
                             stretch))
                 stretch))

  (widget-show! win)
  (process-events! 120)

  (define out-path
    (vector-ref (current-command-line-arguments) 0))
  (define png (widget-grab-png win))
  (call-with-output-file out-path
    (lambda (out) (write-bytes png out))
    #:exists 'replace)
  (eprintf "showcase: wrote ~a (~a bytes)\n" out-path (bytes-length png))
  (quit!))
