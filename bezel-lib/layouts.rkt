#lang racket/base

;; Layouts. Two usage styles:
;;
;; Tree form (preferred) — (layout! win (vbox a (hbox b c) stretch)):
;;
;;   (layout! win
;;            (vbox #:spacing 8
;;                  (make-label "Name:")
;;                  (make-line-edit)
;;                  (hbox (make-button "OK") stretch)))
;;
;; Imperative form — create layouts with make-vbox etc. and compose with
;; layout-add!/grid-put!/form-row!.
;;
;; Either way, once a widget joins a layout installed on a window, Qt
;; owns it (the layout reparents it); Bezel flips the ownership flag so
;; finalizers stand down.

(provide make-vbox make-hbox make-grid make-form
         vbox hbox grid form
         stretch cell
         layout!
         layout-add!
         layout-add-layout!
         add-stretch!
         set-spacing!
         set-margins!
         grid-put!
         form-row!)

(require racket/match
         "private/errors.rkt"
         "private/objects.rkt"
         "private/raw.rkt")

;; ---- constructors ----------------------------------------------------------

(define (make-vbox)
  (require-application)
  (wrap-handle (ok-handle 'make-vbox (bezel-vbox-new)) 'layout #t))

(define (make-hbox)
  (require-application)
  (wrap-handle (ok-handle 'make-hbox (bezel-hbox-new)) 'layout #t))

(define (make-grid)
  (require-application)
  (wrap-handle (ok-handle 'make-grid (bezel-grid-new)) 'layout #t))

(define (make-form)
  (require-application)
  (wrap-handle (ok-handle 'make-form (bezel-form-new)) 'layout #t))

;; Tree-form markers — vbox/hbox/grid/form are ordinary constructors
;; you can also compose imperatively; `stretch` is the stretch marker.
(define stretch 'stretch)

(struct grid-cell (row col widget row-span col-span) #:transparent)

(define (cell row col widget [row-span 1] [col-span 1])
  (grid-cell row col widget row-span col-span))

(define (vbox #:spacing [spacing #f] #:margins [margins #f] . items)
  (define lay (build-layout (make-vbox) spacing items))
  (when margins (apply set-margins! lay margins))
  lay)

(define (hbox #:spacing [spacing #f] #:margins [margins #f] . items)
  (define lay (build-layout (make-hbox) spacing items))
  (when margins (apply set-margins! lay margins))
  lay)

(define (grid . cells) (build-grid (make-grid) cells))

(define (form . rows) (build-form (make-form) rows))

;; ---- tree builder ------------------------------------------------------------

;; Fill `lay` with `items`; returns the layout. Items: widgets, nested
;; layouts, 'stretch.
(define (build-layout lay spacing items)
  (when spacing (set-spacing! lay spacing))
  (for ([item items])
    (cond
      [(eq? item 'stretch) (add-stretch! lay)]
      [(and (bezel-object? item) (eq? 'layout (bezel-object-kind item)))
       (layout-add-layout! lay item)]
      [(bezel-object? item) (layout-add! lay item)]
      [else
       (raise (exn:fail:bezel
               (format "bezel: bad layout item ~a — expected a widget, a layout, or stretch"
                       item)
               (current-continuation-marks)))]))
  lay)

(define (build-grid lay cells)
  (for ([c cells])
    (match c
      [(grid-cell row col widget rs cs)
       (grid-put! lay row col widget #:row-span rs #:col-span cs)]
      [_ (raise (exn:fail:bezel
                 (format "bezel: bad grid item ~a — expected (cell row col widget)" c)
                 (current-continuation-marks)))]))
  lay)

(define (build-form lay rows)
  (for ([row rows])
    (match row
      [(list (? string? label) widget) (form-row! lay label widget)]
      [(list widget) (form-row! lay #f widget)]
      [_ (raise (exn:fail:bezel
                 (format "bezel: bad form row ~a — expected (list label-string widget)" row)
                 (current-continuation-marks)))]))
  lay)

;; Install a finished layout tree on a widget — the tree form's entry
;; point. Qt takes ownership of the layout and everything inside it.
(define (layout! parent lay)
  (require-alive! 'layout! parent)
  (require-alive! 'layout! lay)
  (ok! 'layout!
       (if (eq? 'window (bezel-object-kind parent))
           ;; QMainWindow owns its built-in layout; Qt requires the
           ;; central-widget route there.
           (bezel-window-central-layout (ptr-of parent) (ptr-of lay))
           (bezel-widget-set-layout (ptr-of parent) (ptr-of lay))))
  (adopt-by-qt! lay)
  lay)

;; ---- imperative API ------------------------------------------------------------

(define (layout-add! lay w [stretch-n 0])
  (require-alive! 'layout-add! lay)
  (require-alive! 'layout-add! w)
  (ok! 'layout-add! (bezel-layout-add-widget (ptr-of lay) (ptr-of w) stretch-n))
  (adopt-by-qt! w))

(define (layout-add-layout! parent child [stretch-n 0])
  (require-alive! 'layout-add-layout! parent)
  (require-alive! 'layout-add-layout! child)
  (ok! 'layout-add-layout!
       (bezel-layout-add-layout (ptr-of parent) (ptr-of child) stretch-n))
  (adopt-by-qt! child))

(define (add-stretch! lay [stretch-n 0])
  (require-alive! 'add-stretch! lay)
  (ok! 'add-stretch! (bezel-layout-add-stretch (ptr-of lay) stretch-n)))

(define (set-spacing! lay spacing)
  (require-alive! 'set-spacing! lay)
  (ok! 'set-spacing! (bezel-layout-set-spacing (ptr-of lay) spacing)))

(define (set-margins! lay left top right bottom)
  (require-alive! 'set-margins! lay)
  (ok! 'set-margins! (bezel-layout-set-margins (ptr-of lay) left top right bottom)))

(define (grid-put! lay row col w #:row-span [row-span 1] #:col-span [col-span 1])
  (require-alive! 'grid-put! lay)
  (require-alive! 'grid-put! w)
  (ok! 'grid-put!
       (bezel-grid-add (ptr-of lay) (ptr-of w) row col row-span col-span))
  (adopt-by-qt! w))

(define (form-row! lay label w)
  (require-alive! 'form-row! lay)
  (require-alive! 'form-row! w)
  (ok! 'form-row!
       (bezel-form-add-row (ptr-of lay) (or label "") (ptr-of w)))
  (adopt-by-qt! w))
