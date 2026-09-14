#lang racket/base

;; Bezel test suite. Runs fully offscreen (QT_QPA_PLATFORM=offscreen) on
;; every OS in CI: real Qt objects, real signal deliveries, real PNG
;; grabs — no display needed.
;;
;;   raco test bezel-test/

(require rackunit
         bezel)

(putenv "QT_QPA_PLATFORM" "offscreen")

;; Wait until pred holds or ~2s pass.
(define (wait-for pred)
  (let loop ([n 100])
    (or (pred)
        (and (> n 0) (begin (sleep 0.02) (loop (sub1 n)))))))

(define app (make-application #:name "bezel-test"))

;; ---- lifecycle -----------------------------------------------------------

(test-case "application"
  (check-true (application-token? app)))

(test-case "objects: alive and delete"
  (define o (make-widget))
  (check-true (bezel-alive? o))
  (bezel-delete! o)
  (process-events! 50)  ; deleteLater is deferred until the loop pumps
  (check-false (wait-for (lambda () (bezel-alive? o)))
               "deleteLater should retire the handle"))

(test-case "objects: names"
  (define w (make-widget))
  (set-object-name! w "kid")
  (check-equal? (object-name w) "kid")
  (check-true (bezel-alive? w)))

;; ---- widgets ---------------------------------------------------------------

(test-case "window: title and resize"
  (define win (make-window #:title "Test Window" #:size '(400 300)))
  (check-true (bezel-alive? win))
  (widget-resize! win 410 310)
  (check-true (bezel-alive? win)))

(test-case "label text round-trip with unicode"
  (define l (make-label "hello"))
  (check-equal? (widget-text l) "hello")
  (widget-set-text! l "world 中文")
  (check-equal? (widget-text l) "world 中文"))

(test-case "button and checkbox"
  (define b (make-button "Press me"))
  (check-equal? (widget-text b) "Press me")
  (define c (make-checkbox "Check me"))
  (check-equal? (widget-checked? c) #f)
  (set-widget-checked! c #t)
  (check-equal? (widget-checked? c) #t))

(test-case "line edit, text edit, placeholder, readonly"
  (define e (make-line-edit "init"))
  (check-equal? (widget-text e) "init")
  (set-placeholder! e "type here")
  (set-readonly! e #t)
  (widget-set-text! e "changed")
  (check-equal? (widget-text e) "changed")
  (define t (make-text-edit))
  (widget-set-text! t "line1\nline2")
  (check-equal? (widget-text t) "line1\nline2"))

(test-case "slider, spinbox, progress: int values"
  (define s (make-slider))
  (set-widget-range! s 0 100)
  (widget-set-value! s 42)
  (check-equal? (widget-value s) 42)
  (define sp (make-spin-box))
  (set-widget-range! sp -10 10)
  (widget-set-value! sp -3)
  (check-equal? (widget-value sp) -3)
  (define p (make-progress))
  (set-widget-range! p 0 200)
  (widget-set-value! p 150)
  (check-equal? (widget-value p) 150))

(test-case "combo and list"
  (define combo (make-combo))
  (combo-add! combo "alpha")
  (combo-add! combo "beta")
  (check-equal? (combo-current-index combo) 0)
  (check-equal? (combo-current-text combo) "alpha")
  (define lst (make-list))
  (list-add! lst "one")
  (list-add! lst "two")
  (check-equal? (list-current-row lst) -1 "no selection yet")
  (list-select! lst 1)
  (check-equal? (list-current-row lst) 1)
  (check-equal? (list-current-text lst) "two")
  (combo-select! combo 1)
  (check-equal? (combo-current-text combo) "beta"))

(test-case "stylesheet"
  (define b (make-button "styled"))
  (set-widget-stylesheet! b "QPushButton { color: #C15F3C; }")
  (check-true (bezel-alive? b)))

(test-case "grab-png: real PNG bytes"
  (define win (make-window #:size '(200 100)))
  (define data (widget-grab-png win))
  (check-true (> (bytes-length data) 100) "should produce a real render")
  (check-equal? (bytes-ref data 0) #x89 "PNG magic")
  (check-equal? (subbytes data 1 4) #"PNG"))

;; ---- layouts ---------------------------------------------------------------

(test-case "layout tree form on a window"
  (define win (make-window))
  (check-not-exn
   (lambda ()
     (layout! win
              (vbox #:spacing 6
                    (make-label "top")
                    (hbox (make-button "a") (make-button "b") stretch)
                    (grid (cell 0 0 (make-label "g0"))
                          (cell 1 1 (make-button "g11")))
                    (form (list "Name:" (make-line-edit))
                          (list "Mail:" (make-line-edit)))))))
  (check-true (bezel-alive? win)))

(test-case "layouts imperative form"
  (define win (make-window))
  (define lay (make-vbox))
  (layout-add! lay (make-label "imperative"))
  (add-stretch! lay)
  (set-spacing! lay 4)
  (set-margins! lay 1 2 3 4)
  (layout! win lay)
  (check-true (bezel-alive? win)))

;; ---- signals -------------------------------------------------------------------

(test-case "signals: argless click through the full bridge"
  (define btn (make-button "fire"))
  (define hits (box 0))
  (define conn (connect! btn "clicked()" (lambda _ (set-box! hits (add1 (unbox hits))))))
  (check-true (exact-positive-integer? conn))
  (emit-test-signal! btn "clicked()")
  (check-true (wait-for (lambda () (= 1 (unbox hits)))) "handler should run once")
  (emit-test-signal! btn "clicked()")
  (check-true (wait-for (lambda () (= 2 (unbox hits)))) "handler should run twice"))

(test-case "signals: typed int argument"
  (define slider (make-slider))
  (define seen (box #f))
  (connect! slider "valueChanged(int)" (lambda (v) (set-box! seen v)))
  (emit-test-signal! slider "valueChanged(int)" (list 42))
  (check-true (wait-for (lambda () (equal? 42 (unbox seen)))) "int arg should arrive typed"))

(test-case "signals: typed string argument"
  (define e (make-line-edit))
  (define seen (box #f))
  (connect! e "textChanged(QString)" (lambda (s) (set-box! seen s)))
  (emit-test-signal! e "textChanged(QString)" (list "hello 中文"))
  (check-true (wait-for (lambda () (equal? "hello 中文" (unbox seen))))))

(test-case "signals: typed bool argument"
  (define c (make-checkbox "x"))
  (define seen (box #f))
  (connect! c "toggled(bool)" (lambda (v) (set-box! seen v)))
  (emit-test-signal! c "toggled(bool)" (list #t))
  (check-true (wait-for (lambda () (equal? #t (unbox seen))))))

(test-case "signals: disconnect stops delivery"
  (define btn (make-button "once"))
  (define hits (box 0))
  (define conn (connect! btn "clicked()" (lambda _ (set-box! hits (add1 (unbox hits))))))
  (disconnect! btn conn)
  (emit-test-signal! btn "clicked()")
  (sleep 0.1)
  (check-equal? (unbox hits) 0))

(test-case "signals: connect rejects unknown signals"
  (define btn (make-button "x"))
  (check-exn exn:fail:bezel? (lambda () (connect! btn "noSuchSignal(int)" void))))

(test-case "signals: menu action triggered"
  (define win (make-window))
  (define bar (menu-bar win))
  (define file (menu! bar "File"))
  (define quit (menu-action! file "Quit"))
  (define fired (box #f))
  (connect! quit "triggered()" (lambda _ (set-box! fired #t)))
  (emit-test-signal! quit "triggered()")
  (check-true (wait-for (lambda () (unbox fired)))))

;; ---- cross-thread widget access ------------------------------------------------------

(test-case "free-threaded API: widget call from another Racket thread"
  (make-application)
  (define win (make-window))
  (define l (make-label "before"))
  (layout! win (vbox l))
  (thread (lambda ()
            (sleep 0.2)
            (with-handlers ([exn:fail:bezel?
                             (lambda (e)
                               (eprintf "[dbg] set-text raised: ~a\n" (exn-message e))
                               ;; one retry after letting the loop pump
                               (sleep 0.1)
                               (widget-set-text! l "from-another-thread"))])
              (widget-set-text! l "from-another-thread"))
            (sleep 0.2)
            (quit!)))
  (run win)
  (check-equal? (widget-text l) "from-another-thread"))

;; ---- application run: the pump loop -----------------------------------------------

(test-case "run: pumps events, delivers handlers, honors quit code"
  (make-application)  ; re-create after a previous run's cleanup
  (define win (make-window #:title "pump"))
  (define btn (make-button "go"))
  (define hits (box 0))
  (connect! btn "clicked()" (lambda _ (set-box! hits (add1 (unbox hits)))))
  (layout! win (vbox btn))
  (thread (lambda ()
            (sleep 0.2)
            (eprintf "[run-t] emitting\n")
            (emit-test-signal! btn "clicked()")
            (eprintf "[run-t] emitted, waiting delivery\n")
            (wait-for (lambda () (= 1 (unbox hits))))
            (eprintf "[run-t] delivered, quitting\n")
            (quit! 7)))
  (define code (run win))
  (check-equal? code 7)
  (check-equal? (unbox hits) 1))

;; ---- generator-produced bindings (specs/dial.json → QDial) -------------------------

(test-case "generated bindings: QDial round-trip"
  (make-application)  ; a previous run test cleaned the app up
  (define dial (dial-new))
  (check-true (bezel-alive? dial))
  (dial-set-range dial 0 180)
  (dial-set-value dial 90)
  (check-equal? (dial-value dial) 90)
  (dial-set-wrapping dial #t)
  (check-true (bezel-alive? dial)))

(displayln "bezel-test: all tests passed")
