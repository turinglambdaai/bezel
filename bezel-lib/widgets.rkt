#lang racket/base

;; Widgets: constructors and the shared widget API.
;;
;; Every constructor takes an optional parent. With a parent, Qt owns
;; the object; without one, Bezel keeps it alive until explicit deletion
;; or application teardown. There are deliberately no deleting GC
;; finalizers (see private/objects.rkt).

(provide make-window
         make-widget
         make-label
         make-button
         make-checkbox
         make-line-edit
         make-text-edit
         make-combo
         make-spin-box
         make-slider
         make-progress
         make-list-widget
         make-table-widget

         widget-show!
         widget-hide!
         widget-close!
         widget-enabled?
         set-widget-enabled!
         widget-resize!
         widget-move!
         set-window-title!
         set-widget-stylesheet!
         set-tooltip!
         widget-tooltip
         widget-width
         widget-height
         widget-x
         widget-y
         center-widget!

         widget-set-text!
         widget-text
         set-widget-checked!
         widget-checked?
         widget-set-value!
         widget-value
         set-widget-range!
         combo-add!
         combo-select!
         combo-current-index
         combo-current-text
         list-add!
         list-select!
         list-current-row
         list-current-text
         set-placeholder!
         set-readonly!

         table-set-dimensions!
         table-row-count
         table-column-count
         table-set-header-labels!
         table-set-cell-text!
         table-cell-text

         widget-grab-png)

(require ffi/unsafe
         "private/errors.rkt"
         "private/objects.rkt"
         "private/raw.rkt")

;; Create + wrap a widget with the standard parent/ownership rule.
;; `build` receives the resolved parent pointer (or #f) and constructs
;; the raw handle; a null parent means the object is top-level from Qt's
;; ownership perspective.
(define (spawn who build parent)
  (require-application)
  (when parent (require-alive! who parent))
  (wrap-handle (ok-handle who (build (and parent (ptr-of parent))))
               'widget (not parent)))

;; Constructors accept the parent positionally (make-label "x" win) or as
;; the #:parent keyword (make-label "x" #:parent win). Passing both is an
;; error — silent precedence would hide copy-paste mistakes.
(define (resolve-parent-arg who positional kw)
  (when (and positional kw)
    (raise
     (exn:fail:bezel
      (format "bezel: ~a: parent given twice — pass it positionally or with #:parent, not both"
              who)
      (current-continuation-marks))))
  (or kw positional))

;; ---- constructors ---------------------------------------------------------

;; (make-window #:title "..." #:size '(w h) #:stylesheet "qss")
(define (make-window #:title [title #f]
                     #:size [size #f]
                     #:stylesheet [stylesheet #f])
  (require-application)
  (define win (wrap-handle (ok-handle 'make-window (bezel-window-new)) 'window #t))
  (when title (set-window-title! win title))
  (when size (widget-resize! win (car size) (cadr size)))
  (when stylesheet (set-widget-stylesheet! win stylesheet))
  win)

(define (make-widget [parent #f] #:parent [kw-parent #f])
  (spawn 'make-widget (lambda (p) (bezel-widget-new p))
         (resolve-parent-arg 'make-widget parent kw-parent)))

(define (make-label text [parent #f] #:parent [kw-parent #f])
  (spawn 'make-label (lambda (p) (bezel-label-new text p))
         (resolve-parent-arg 'make-label parent kw-parent)))

(define (make-button text [parent #f] #:parent [kw-parent #f])
  (spawn 'make-button (lambda (p) (bezel-button-new text p))
         (resolve-parent-arg 'make-button parent kw-parent)))

(define (make-checkbox text [parent #f] #:parent [kw-parent #f])
  (spawn 'make-checkbox (lambda (p) (bezel-checkbox-new text p))
         (resolve-parent-arg 'make-checkbox parent kw-parent)))

(define (make-line-edit [text ""] [parent #f] #:parent [kw-parent #f])
  (spawn 'make-line-edit (lambda (p) (bezel-lineedit-new text p))
         (resolve-parent-arg 'make-line-edit parent kw-parent)))

(define (make-text-edit [parent #f] #:parent [kw-parent #f])
  (spawn 'make-text-edit (lambda (p) (bezel-textedit-new p))
         (resolve-parent-arg 'make-text-edit parent kw-parent)))

(define (make-combo [parent #f] #:parent [kw-parent #f])
  (spawn 'make-combo (lambda (p) (bezel-combo-new p))
         (resolve-parent-arg 'make-combo parent kw-parent)))

(define (make-spin-box [parent #f] #:parent [kw-parent #f])
  (spawn 'make-spin-box (lambda (p) (bezel-spinbox-new p))
         (resolve-parent-arg 'make-spin-box parent kw-parent)))

;; (make-slider #:vertical? #t) for a vertical slider.
(define (make-slider #:vertical? [vertical? #f] [parent #f] #:parent [kw-parent #f])
  (spawn 'make-slider (lambda (p) (bezel-slider-new (if vertical? 1 0) p))
         (resolve-parent-arg 'make-slider parent kw-parent)))

(define (make-progress [parent #f] #:parent [kw-parent #f])
  (spawn 'make-progress (lambda (p) (bezel-progress-new p))
         (resolve-parent-arg 'make-progress parent kw-parent)))

;; Named make-list-widget (not make-list) to avoid clashing with
;; racket/list's make-list.
(define (make-list-widget [parent #f] #:parent [kw-parent #f])
  (spawn 'make-list-widget (lambda (p) (bezel-list-new p))
         (resolve-parent-arg 'make-list-widget parent kw-parent)))

;; QTableWidget — see the table-* API at the bottom of this module.
(define (make-table-widget [parent #f] #:parent [kw-parent #f])
  (spawn 'make-table-widget (lambda (p) (bezel-table-new p))
         (resolve-parent-arg 'make-table-widget parent kw-parent)))

;; ---- QWidget shared API ------------------------------------------------------

(define (widget-show! w)
  (require-alive! 'widget-show! w)
  (ok! 'widget-show! (bezel-widget-show (ptr-of w))))

(define (widget-hide! w)
  (require-alive! 'widget-hide! w)
  (ok! 'widget-hide! (bezel-widget-hide (ptr-of w))))

;; Close a widget (close event; for top-level windows this participates
;; in quit-on-last-window-closed).
(define (widget-close! w)
  (require-alive! 'widget-close! w)
  (ok! 'widget-close! (bezel-widget-close (ptr-of w))))

(define (widget-enabled? w)
  (require-alive! 'widget-enabled? w)
  (define r (bezel-widget-is-enabled (ptr-of w)))
  (cond [(= r -1) (raise-bezel-error 'widget-enabled?)] [(= r 1) #t] [else #f]))

(define (set-widget-enabled! w enabled?)
  (require-alive! 'set-widget-enabled! w)
  (ok! 'set-widget-enabled! (bezel-widget-set-enabled (ptr-of w) (if enabled? 1 0))))

(define (widget-resize! w width height)
  (require-alive! 'widget-resize! w)
  (ok! 'widget-resize! (bezel-widget-resize (ptr-of w) width height)))

(define (widget-move! w x y)
  (require-alive! 'widget-move! w)
  (ok! 'widget-move! (bezel-widget-move (ptr-of w) x y)))

(define (set-window-title! w title)
  (require-alive! 'set-window-title! w)
  (ok! 'set-window-title! (bezel-window-set-title (ptr-of w) title)))

;; Qt Style Sheets — style any widget with a CSS dialect. This is the
;; single biggest styling win over racket/gui.
(define (set-widget-stylesheet! w qss)
  (require-alive! 'set-widget-stylesheet! w)
  (ok! 'set-widget-stylesheet! (bezel-widget-set-stylesheet (ptr-of w) qss)))

;; ---- tooltips ---------------------------------------------------------------

(define (set-tooltip! w text)
  (require-alive! 'set-tooltip! w)
  (ok! 'set-tooltip! (bezel-widget-set-tooltip (ptr-of w) text)))

(define (widget-tooltip w)
  (require-alive! 'widget-tooltip w)
  (define p (ok-string 'widget-tooltip (bezel-widget-tooltip (ptr-of w))))
  (begin0 (cstring->string/utf8 p)
    (bezel-free p)))

;; ---- geometry ----------------------------------------------------------------
;;
;; Like widget-value: -1 legitimately means "no selection"-style values
;; never occur here, so -1 is an error only when the shim also produced
;; a fresh error message (dead/unknown handle).

(define (geometry-ref who r)
  (when (and (= r -1) (last-error)) (raise-bezel-error who))
  r)

(define (widget-width w)
  (require-alive! 'widget-width w)
  (geometry-ref 'widget-width (bezel-widget-width (ptr-of w))))

(define (widget-height w)
  (require-alive! 'widget-height w)
  (geometry-ref 'widget-height (bezel-widget-height (ptr-of w))))

(define (widget-x w)
  (require-alive! 'widget-x w)
  (geometry-ref 'widget-x (bezel-widget-x (ptr-of w))))

(define (widget-y w)
  (require-alive! 'widget-y w)
  (geometry-ref 'widget-y (bezel-widget-y (ptr-of w))))

;; Center inside the parent widget, or on the screen when top-level.
(define (center-widget! w)
  (require-alive! 'center-widget! w)
  (ok! 'center-widget! (bezel-widget-center (ptr-of w))))

;; ---- value API ------------------------------------------------------------------

(define (widget-set-text! w text)
  (require-alive! 'widget-set-text! w)
  (ok! 'widget-set-text! (bezel-widget-set-text (ptr-of w) text)))

(define (widget-text w)
  (require-alive! 'widget-text w)
  (define p (ok-string 'widget-text (bezel-widget-text (ptr-of w))))
  (begin0 (cstring->string/utf8 p)
    (bezel-free p)))

(define (set-widget-checked! w checked?)
  (require-alive! 'set-widget-checked! w)
  (ok! 'set-widget-checked! (bezel-widget-set-checked (ptr-of w) (if checked? 1 0))))

(define (widget-checked? w)
  (require-alive! 'widget-checked? w)
  (define r (bezel-widget-is-checked (ptr-of w)))
  (cond [(= r -1) (raise-bezel-error 'widget-checked?)] [(= r 1) #t] [else #f]))

(define (widget-set-value! w value)
  (require-alive! 'widget-set-value! w)
  (ok! 'widget-set-value! (bezel-widget-set-value (ptr-of w) value)))

;; Several Qt getters legitimately return -1 (for example "no selection").
;; The shim clears its thread-local error at every ABI entry, so -1 is an
;; error only when that same call also produced a fresh error string.
(define (value-or-error who r)
  (when (and (= r -1) (last-error)) (raise-bezel-error who))
  r)

(define (widget-value w)
  (require-alive! 'widget-value w)
  (value-or-error 'widget-value (bezel-widget-value (ptr-of w))))

(define (set-widget-range! w min max)
  (require-alive! 'set-widget-range! w)
  (ok! 'set-widget-range! (bezel-widget-set-range (ptr-of w) min max)))

(define (combo-add! combo item)
  (require-alive! 'combo-add! combo)
  (ok! 'combo-add! (bezel-combo-add (ptr-of combo) item)))

(define (combo-current-index combo)
  (require-alive! 'combo-current-index combo)
  (value-or-error 'combo-current-index (bezel-combo-current-index (ptr-of combo))))

(define (combo-current-text combo)
  (require-alive! 'combo-current-text combo)
  (define p (ok-string 'combo-current-text (bezel-combo-current-text (ptr-of combo))))
  (begin0 (cstring->string/utf8 p)
    (bezel-free p)))

(define (list-add! lst item)
  (require-alive! 'list-add! lst)
  (ok! 'list-add! (bezel-list-add (ptr-of lst) item)))

(define (list-select! lst row)
  (require-alive! 'list-select! lst)
  (ok! 'list-select! (bezel-list-set-current-row (ptr-of lst) row)))

(define (combo-select! combo index)
  (require-alive! 'combo-select! combo)
  (ok! 'combo-select! (bezel-combo-set-index (ptr-of combo) index)))

(define (list-current-row lst)
  (require-alive! 'list-current-row lst)
  (value-or-error 'list-current-row (bezel-list-current-row (ptr-of lst))))

(define (list-current-text lst)
  (require-alive! 'list-current-text lst)
  (define p (ok-string 'list-current-text (bezel-list-current-text (ptr-of lst))))
  (begin0 (cstring->string/utf8 p)
    (bezel-free p)))

(define (set-placeholder! w text)
  (require-alive! 'set-placeholder! w)
  (ok! 'set-placeholder! (bezel-widget-set-placeholder (ptr-of w) text)))

(define (set-readonly! w readonly?)
  (require-alive! 'set-readonly! w)
  (ok! 'set-readonly! (bezel-widget-set-readonly (ptr-of w) (if readonly? 1 0))))

;; ---- tables --------------------------------------------------------------------
;;
;; QTableWidget with plain-text cells. Header labels use Qt's
;; '\n'-separated convention: (table-set-header-labels! t "Name\nScore").

(define (table-set-dimensions! t rows cols)
  (require-alive! 'table-set-dimensions! t)
  (ok! 'table-set-dimensions! (bezel-table-set-dimensions (ptr-of t) rows cols)))

(define (table-row-count t)
  (require-alive! 'table-row-count t)
  (geometry-ref 'table-row-count (bezel-table-row-count (ptr-of t))))

(define (table-column-count t)
  (require-alive! 'table-column-count t)
  (geometry-ref 'table-column-count (bezel-table-column-count (ptr-of t))))

(define (table-set-header-labels! t labels)
  (require-alive! 'table-set-header-labels! t)
  (ok! 'table-set-header-labels! (bezel-table-set-header-labels (ptr-of t) labels)))

(define (table-set-cell-text! t row col text)
  (require-alive! 'table-set-cell-text! t)
  (ok! 'table-set-cell-text! (bezel-table-set-cell-text (ptr-of t) row col text)))

(define (table-cell-text t row col)
  (require-alive! 'table-cell-text t)
  (define p (ok-string 'table-cell-text (bezel-table-cell-text (ptr-of t) row col)))
  (begin0 (cstring->string/utf8 p)
    (bezel-free p)))

;; ---- verification ----------------------------------------------------------------

;; Render the widget into PNG bytes — the agent-friendly counterpart of
;; glaze's webview-capture!: tests assert on UI state without a human.
(define (widget-grab-png w)
  (require-alive! 'widget-grab-png w)
  (define len-p (malloc _int 'raw))
  (define data #f)
  (dynamic-wind
    void
    (lambda ()
      (ptr-set! len-p _int 0)
      (set! data (bezel-widget-grab-png (ptr-of w) len-p))
      (unless data (raise-bezel-error 'widget-grab-png))
      (define len (ptr-ref len-p _int))
      (when (< len 0)
        (raise
         (exn:fail:bezel
          "bezel: widget-grab-png: native shim returned a negative PNG size"
          (current-continuation-marks))))
      (define bs (make-bytes len))
      (memcpy bs data len)
      bs)
    (lambda ()
      (when data (bezel-free data))
      (free len-p))))
