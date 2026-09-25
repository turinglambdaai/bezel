#lang racket/base

;; Desktop integration and P0 widget coverage: tree, date editor,
;; status bar, toolbar, clipboard, tray. Real Qt objects under
;; offscreen, like the other suites. The tray notification path is
;; deliberately not exercised — posting desktop notifications has no
;; observable offscreen behavior.

(require rackunit
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
    (or (pred) (and (> n 0) (begin (sleep 0.02) (loop (sub1 n)))))))

(make-application #:name "bezel-test-desktop")

;; ---- tree -----------------------------------------------------------------

(test-case "tree: headers, items, children with unicode"
  (define t (make-tree-widget))
  (tree-set-header-labels! t "Name\nKind")
  (check-equal? (tree-column-count t) 2)
  (check-equal? (tree-add! t "src\nfolder") 0)
  (check-equal? (tree-add! t "main.rkt\nfile") 1)
  (check-equal? (tree-count t) 2)
  (check-equal? (tree-add-child! t 0 "core.rkt\nfile") 0)
  (check-equal? (tree-add-child! t 0 "gui.rkt\nfile") 1)
  (check-equal? (tree-child-count t 0) 2)
  (check-equal? (tree-item-text t 1 0) "main.rkt")
  (check-equal? (tree-item-text t 1 1) "file")
  (check-equal? (tree-child-text t 0 1 0) "gui.rkt")
  (tree-set-item-text! t 1 0 "入口.rkt")
  (check-equal? (tree-item-text t 1 0) "入口.rkt")
  (tree-set-child-text! t 0 0 1 "文件")
  (check-equal? (tree-child-text t 0 0 1) "文件"))

(test-case "tree: selection and expansion"
  (define t (make-tree-widget))
  (tree-add! t "alpha")
  (tree-add! t "beta")
  (check-equal? (tree-current-row t) -1 "no selection yet")
  (tree-select! t 1)
  (check-equal? (tree-current-row t) 1)
  (tree-add-child! t 0 "child")
  (check-not-exn (lambda () (tree-set-item-expanded! t 0 #t)))
  (check-true (bezel-alive? t)))

(test-case "tree: out-of-range rows raise bezel errors"
  (define t (make-tree-widget))
  (tree-add! t "only")
  (check-exn exn:fail:bezel? (lambda () (tree-item-text t 9 0)))
  (check-exn exn:fail:bezel? (lambda () (tree-add-child! t 9 "x")))
  (check-exn exn:fail:bezel? (lambda () (tree-select! t 9))))

(test-case "tree: clear resets contents"
  (define t (make-tree-widget))
  (tree-add! t "a")
  (tree-add! t "b")
  (tree-clear! t)
  (check-equal? (tree-count t) 0)
  (check-equal? (tree-current-row t) -1))

;; ---- date editor -------------------------------------------------------------

(test-case "dateedit: set/get round-trip"
  (define e (make-date-edit))
  (dateedit-set-date! e 2026 9 24)
  (check-equal? (dateedit-date e) '(2026 9 24))
  (dateedit-set-date! e 2000 2 29)  ; leap day is valid
  (check-equal? (dateedit-date e) '(2000 2 29)))

(test-case "dateedit: options and invalid dates"
  (define e (make-date-edit))
  (dateedit-set-calendar-popup! e #t)
  (dateedit-set-display-format! e "yyyy-MM-dd")
  (check-not-exn (lambda () (dateedit-set-date! e 2026 12 31)))
  (check-exn exn:fail:bezel? (lambda () (dateedit-set-date! e 2026 13 1)))
  (check-exn exn:fail:bezel? (lambda () (dateedit-set-date! e 2026 0 10)))
  (check-true (bezel-alive? e)))

;; ---- status bar + toolbar ---------------------------------------------------

(test-case "status bar: show, read, clear"
  (define win (make-window))
  (define sb (window-status-bar win))
  (check-true (bezel-alive? sb))
  (status-show-message! sb "Ready" 5000)
  (check-equal? (status-current-message sb) "Ready")
  (status-show-message! sb "就绪 中文" 0)
  (check-equal? (status-current-message sb) "就绪 中文")
  (status-clear-message! sb)
  (check-equal? (status-current-message sb) ""))

(test-case "toolbar: actions are connectable"
  (define win (make-window))
  (define bar (window-toolbar win "Main"))
  (check-true (bezel-alive? bar))
  (define act (toolbar-add-action! bar "Refresh"))
  (define fired (box #f))
  (connect! act "triggered()" (lambda _ (set-box! fired #t)))
  (emit-test-signal! act "triggered()")
  (check-not-false (wait-for (lambda () (unbox fired)))))

;; ---- clipboard + tray -----------------------------------------------------------

(test-case "clipboard round-trip"
  (clipboard-set-text! "bezel clipboard 中文")
  (check-equal? (clipboard-text) "bezel clipboard 中文"))

(test-case "tray: construct, tooltip, menu wiring (no display)"
  (define tray (make-tray "" "Bezel test tray"))
  (check-true (bezel-alive? tray))
  (set-tray-tooltip! tray "updated tooltip")
  ;; A menu handle for the context menu (menus work offscreen).
  (define win (make-window))
  (define m (menu! (menu-bar win) "Tray"))
  (menu-action! m "Quit")
  (tray-set-menu! tray m)
  (check-not-exn (lambda () (tray-hide! tray)))
  (check-true (bezel-alive? tray)))

(test-case "window title readback, visibility, focus"
  (define win (make-window #:title "Readable 标题"))
  (check-equal? (widget-window-title win) "Readable 标题")
  (set-window-title! win "Renamed")
  (check-equal? (widget-window-title win) "Renamed")
  (check-false (widget-visible? win) "never shown yet")
  (widget-show! win)
  (check-true (widget-visible? win))
  (define field (make-line-edit "type here"))
  (layout! win (vbox field))
  (check-not-exn (lambda () (widget-focus! field))))

(test-case "typed (int,int) signals: both arguments arrive"
  ;; splitterMoved(int,int): same (int,int) shape as cellChanged
  (define sp (splitter-new))
  (splitter-add-widget sp (make-label "a"))
  (splitter-add-widget sp (make-label "b"))
  (define seen (box #f))
  (connect! sp "splitterMoved(int,int)" (lambda (pos index) (set-box! seen (list pos index))))
  (emit-test-signal! sp "splitterMoved(int,int)" (list 10 20))
  (check-true (wait-for (lambda () (equal? (list 10 20) (unbox seen))))
              "both int arguments should arrive typed"))

(displayln "bezel-test/desktop: all tests passed")
