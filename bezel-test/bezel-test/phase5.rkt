#lang racket/base

;; Phase 5 coverage: generator-produced widget classes (radio, groupbox,
;; doublespin, lcd, tabs, stacked, splitter, richtext), the handwritten
;; table widget, tooltips/geometry/shortcuts, timer ergonomics, and the
;; #:parent keyword form. Real Qt objects under offscreen, same as
;; main.rkt. Runs in its own process (its own QApplication lifecycle).

(require rackunit
         racket/string
         bezel)

(when (getenv "BEZEL_TEST_PROGRESS")
  (current-test-case-around
   (lambda (thunk)
     (eprintf "[case] ~a\n" (current-test-name))
     (flush-output)
     (thunk))))

(putenv "QT_QPA_PLATFORM" "offscreen")

(define (wait-for pred [n 100])
  (let loop ([n n])
    (or (pred)
        (and (> n 0) (begin (sleep 0.02) (loop (sub1 n)))))))

(make-application #:name "bezel-test-phase5")

;; ---- generated bindings: checkable / container widgets ----------------------

(test-case "radio: text and check state round-trip"
  (define a (radio-new "Plan A"))
  (define b (radio-new "Plan B"))
  (check-equal? (radio-text a) "Plan A")
  (check-equal? (radio-is-checked a) #f)
  (radio-set-checked a #t)
  (check-equal? (radio-is-checked a) #t)
  (radio-set-text b "方案 B 中文")
  (check-equal? (radio-text b) "方案 B 中文"))

(test-case "groupbox: title, checkable, and layouts inside"
  (define gb (groupbox-new "Settings"))
  (check-equal? (groupbox-title gb) "Settings")
  (groupbox-set-title gb "高级设置")
  (check-equal? (groupbox-title gb) "高级设置")
  (check-equal? (groupbox-is-checkable gb) #f)
  (groupbox-set-checkable gb #t)
  (check-equal? (groupbox-is-checkable gb) #t)
  ;; a QGroupBox is a plain QWidget: the tree layout API applies
  (check-not-exn
   (lambda () (layout! gb (vbox (make-label "inside the group")))))
  (check-true (bezel-alive? gb)))

(test-case "doublespin: double values, decimals, prefix/suffix"
  (define d (doublespin-new))
  (doublespin-set-range d -100.0 100.0)
  (doublespin-set-decimals d 3)
  (doublespin-set-single-step d 0.125)
  (doublespin-set-value d -12.5)
  (check-equal? (doublespin-value d) -12.5)
  (doublespin-set-prefix d "$")
  (doublespin-set-suffix d " kg")
  (check-true (bezel-alive? d)))

(test-case "lcd: display int values"
  (define n (lcd-new))
  (lcd-set-digit-count n 4)
  (lcd-display n 42)
  (check-equal? (lcd-value n) 42.0))

;; ---- generated bindings: container widgets -----------------------------------

(test-case "tabs: pages, current index, tab text"
  (define t (tabs-new))
  (define page1 (make-label "one"))
  (define page2 (make-label "two"))
  (check-true (>= (tabs-add t page1 "First") 0))
  (check-true (>= (tabs-add t page2 "Second") 0))
  (check-equal? (tabs-count t) 2)
  (check-equal? (tabs-current-index t) -1 "no page selected yet")
  (tabs-set-current-index t 1)
  (check-equal? (tabs-current-index t) 1)
  (check-equal? (tabs-tab-text t 0) "First")
  (tabs-set-tab-text t 1 "第二章")
  (check-equal? (tabs-tab-text t 1) "第二章")
  (check-true (bezel-alive? page1))
  (check-true (bezel-alive? page2)))

(test-case "tabs: typed currentChanged signal through the bridge"
  (define t (tabs-new))
  (tabs-add t (make-label "a") "A")
  (tabs-add t (make-label "b") "B")
  (define seen (box #f))
  (connect! t "currentChanged(int)" (lambda (v) (set-box! seen v)))
  (emit-test-signal! t "currentChanged(int)" (list 1))
  (check-true (wait-for (lambda () (equal? 1 (unbox seen))))))

(test-case "stacked: pages and current index"
  (define s (stacked-new))
  (stacked-add s (make-label "p1"))
  (stacked-add s (make-label "p2"))
  (check-equal? (stacked-count s) 2)
  (stacked-set-current-index s 0)
  (check-equal? (stacked-current-index s) 0)
  (stacked-set-current-index s 1)
  (check-equal? (stacked-current-index s) 1))

(test-case "splitter: widgets, orientation, stretch"
  (define sp (splitter-new))
  (check-not-exn (lambda () (splitter-add-widget sp (make-label "left"))))
  (check-not-exn (lambda () (splitter-add-widget sp (make-label "right"))))
  ;; 2 = Qt::Vertical, the generator's orientation argument
  (splitter-set-orientation sp 2)
  (check-not-exn (lambda () (splitter-set-stretch-factor sp (make-label "x") 1)))
  (check-not-exn (lambda () (splitter-set-handle-width sp 4)))
  (check-true (bezel-alive? sp)))

(test-case "richtext: html and plain text"
  (define e (richtext-new "seed"))
  (check-equal? (richtext-to-plain-text e) "seed")
  (richtext-set-plain-text e "line")
  (richtext-append e "more 中文")
  (check-equal? (richtext-to-plain-text e) "line\nmore 中文")
  (richtext-set-html e "<b>bold</b>")
  (check-pred string-contains? (richtext-html e) "bold")
  (richtext-clear e)
  (check-equal? (richtext-to-plain-text e) ""))

;; ---- handwritten: table widget ------------------------------------------------

(test-case "table: dimensions, headers, cells with unicode"
  (define t (make-table-widget))
  (table-set-dimensions! t 2 3)
  (check-equal? (table-row-count t) 2)
  (check-equal? (table-column-count t) 3)
  (table-set-header-labels! t "Name\nScore\n备注")
  (table-set-cell-text! t 0 0 "Ada")
  (table-set-cell-text! t 1 2 "九十九")
  (check-equal? (table-cell-text t 0 0) "Ada")
  (check-equal? (table-cell-text t 1 2) "九十九")
  (check-equal? (table-cell-text t 0 1) "" "unset cells read as empty"))

(test-case "table: out-of-range cells raise bezel errors"
  (define t (make-table-widget))
  (table-set-dimensions! t 1 1)
  (check-exn exn:fail:bezel? (lambda () (table-set-cell-text! t 5 5 "x")))
  (check-exn exn:fail:bezel? (lambda () (table-cell-text t 5 5))))

;; ---- handwritten: tooltips / geometry / shortcut ------------------------------

(test-case "tooltip round-trip"
  (define b (make-button "hover"))
  (check-equal? (widget-tooltip b) "")
  (set-tooltip! b "点击这里 Click here")
  (check-equal? (widget-tooltip b) "点击这里 Click here"))

(test-case "geometry: width/height after resize"
  (define w (make-widget))
  (widget-resize! w 123 45)
  (process-events! 50)
  (check-equal? (widget-width w) 123)
  (check-equal? (widget-height w) 45))

(test-case "geometry: centering is callable headlessly"
  (define win (make-window #:size '(200 100)))
  (check-not-exn (lambda () (center-widget! win)))
  (check-true (bezel-alive? win))
  (define-values (x y) (values (widget-x win) (widget-y win)))
  (check-true (and (integer? x) (integer? y))))

(test-case "menu action shortcut"
  (define win (make-window))
  (define act (menu-action! (menu! (menu-bar win) "File") "Quit"))
  (check-not-exn (lambda () (set-action-shortcut! act "Ctrl+Q")))
  (check-true (bezel-alive? act)))

;; ---- ergonomics -----------------------------------------------------------------

(test-case "#:parent keyword form and double-parent rejection"
  (define win (make-window))
  (define child (make-label "kid" #:parent win))
  (check-true (bezel-alive? child))
  (check-false (bezel-object-owned child) "#:parent transfers ownership to Qt")
  (check-exn exn:fail:bezel?
             (lambda () (make-label "oops" win #:parent win))))

(test-case "generated constructors take a positional parent too"
  (define win (make-window))
  (define gb (groupbox-new "nested" win))
  (check-true (bezel-alive? gb))
  (check-false (bezel-object-owned gb)))

(test-case "timers: after! fires once"
  (define fired (box #f))
  (after! 50 (lambda () (set-box! fired #t)))
  (check-true (wait-for (lambda () (unbox fired)) 150) "after! should fire"))

(test-case "timers: every! repeats and stop-timer! stops"
  (define n (box 0))
  (define t (every! 40 (lambda () (set-box! n (add1 (unbox n))))))
  (check-true (wait-for (lambda () (>= (unbox n) 3)) 200) "every! should tick")
  (stop-timer! t)
  (define at-stop (unbox n))
  (sleep 0.15)
  (check-equal? (unbox n) at-stop "no ticks after stop-timer!")
  (check-false (bezel-timer-running? t)))

(test-case "timers: widget calls from a timer marshal to the GUI thread"
  (define l (make-label "waiting"))
  (define t (after! 50 (lambda () (widget-set-text! l "from timer"))))
  (check-true (wait-for (lambda () (equal? "from timer" (widget-text l))) 300)
              "timer handler should update the label"))

(displayln "bezel-test/phase5: all tests passed")
