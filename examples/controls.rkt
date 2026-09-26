#lang racket/base

;; Phase 5 widget tour: tabs, stacked pages, splitter, group box, radio,
;; double spin box, LCD, table, rich text, timers. Run:
;;   racket examples/controls.rkt

(require bezel
         racket/format)

(make-application #:name "Bezel Controls")

(define tabs (tabs-new))
(define status (make-label "Home page: the File menu stops the clock."))
(define dial (dial-new))
(dial-set-range dial 0 180)
(define page-home (make-widget))
(layout! page-home
         (vbox #:margins '(12 12 12 12)
               status
               (make-label "Drag the splitter; spin the dial below.")
               dial))
(define about (groupbox-new "About"))
(layout! about (vbox (make-label "Bezel — Qt 6 for Racket")
                     (richtext-new "<b>Rich text</b> with HTML support")))

(tabs-add tabs page-home "Home")
(tabs-add tabs about "About")

;; A clock: LCD + slider driven by every!.
(define clock (lcd-new))
(lcd-set-digit-count clock 4)
(define slider (make-slider))
(set-widget-range! slider 0 999)
(connect! slider "valueChanged(int)" (lambda (v) (lcd-display clock v)))
(define ticker (every! 100 (lambda ()
                             (widget-set-value! slider (random 1000)))))

;; Double spin box with prefix/suffix inside a splitter.
(define amount (doublespin-new))
(doublespin-set-range amount 0.0 100.0)
(doublespin-set-decimals amount 2)
(doublespin-set-single-step amount 0.25)
(doublespin-set-prefix amount "$")
(doublespin-set-suffix amount " / item")

(define table (make-table-widget))
(table-set-dimensions! table 2 2)
(table-set-header-labels! table "Item\nQty")
(table-set-cell-text! table 0 0 "Widget")
(table-set-cell-text! table 0 1 "12")
(table-set-cell-text! table 1 0 "Dial")
(table-set-cell-text! table 1 1 "3")

(define left (vbox (make-label "Amount") amount (make-label "Table") table))
(define right (vbox (make-label "Clock") clock slider))
(define split (splitter-new))
(splitter-add-widget split left)
(splitter-add-widget split right)

;; Menu with a real keyboard shortcut.
(define win (make-window #:title "Bezel Controls" #:size '(560 400)))
(define file-menu (menu! (menu-bar win) "File"))
(define stop-action (menu-action! file-menu "Stop clock"))
(connect! stop-action "triggered()" (lambda _ (stop-timer! ticker)))
(define quit-action (menu-action! file-menu "Quit"))
(set-action-shortcut! quit-action "Ctrl+Q")
(connect! quit-action "triggered()" (lambda _ (quit!)))

;; Phase 5 chrome: status bar + toolbar + tray + clipboard + tree/date.
(status-show-message! (window-status-bar win) "Ready — the File menu stops the clock")
(define refresh (toolbar-add-action! (window-toolbar win "Main") "Refresh"))
(connect! refresh "triggered()"
          (lambda _
            (clipboard-set-text! (format "clock=~a" (lcd-value clock)))
            (status-show-message! (window-status-bar win) "Clock copied to clipboard")))

(define tree (make-tree-widget))
(tree-set-header-labels! tree "Asset\nKind")
(define root-row (tree-add! tree "src\nfolder"))
(tree-add-child! tree root-row "controls.rkt\nfile")
(tree-select! tree root-row)

(define until (make-date-edit))
(dateedit-set-calendar-popup! until #t)
(dateedit-set-date! until 2026 12 31)

(define tray (make-tray "" "Bezel Controls"))
(tray-set-menu! tray file-menu)
(tray-show! tray)

(define count (make-observable 0))
(define count-label (make-label "0"))
(observe! count (lambda (v) (widget-set-text! count-label (~a v))))
(connect! (toolbar-add-action! (window-toolbar win "Main") "+1")
          "triggered()"
          (lambda _ (set-observable! count (add1 (observable-value count)))))

(layout! win (vbox #:margins '(8 8 8 8)
                    tabs split
                    (hbox count-label (make-label "click +1 on the toolbar"))
                    (hbox (make-label "Ship by:") until tree)))
(run win)
