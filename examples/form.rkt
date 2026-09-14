#lang racket/base

;; Form layout, menus, and a typed signal. Run: racket examples/form.rkt

(require bezel
         racket/string)

(define name-field (make-line-edit))
(set-placeholder! name-field "Ada Lovelace")
(define mail-field (make-line-edit))
(set-placeholder! mail-field "ada@example.com")
(define experience (make-slider))
(set-widget-range! experience 0 15)
(define years (make-label "0 years"))
(connect! experience "valueChanged(int)"
          (lambda (v) (widget-set-text! years (format "~a year~a" v (if (= v 1) "" "s")))))

(define win (make-window #:title "Team — Bezel" #:size '(420 240)))
(define bar (menu-bar win))
(define file (menu! bar "File"))
(define quit-action (menu-action! file "Quit"))
(connect! quit-action "triggered()" (lambda _ (quit!)))

(define submit (make-button "Submit"))
(define status (make-label ""))
(connect! submit "clicked()" (lambda _
  (if (non-empty-string? (widget-text name-field))
      (begin (widget-set-text! status (format "Welcome, ~a!" (widget-text name-field)))
             (msg-information "Saved. Check your inbox." #:parent win))
      (msg-warning "Please tell us your name." #:parent win))))

(layout! win
         (vbox #:margins '(20 20 20 20)
               (form (list "Name:" name-field)
                     (list "Mail:" mail-field)
                     (list "Experience:" experience))
               years
               status
               (hbox stretch submit)))

(run win)
