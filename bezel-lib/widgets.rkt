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

         widget-show!
         widget-hide!
         widget-close!
         widget-enabled?
         set-widget-enabled!
         widget-resize!
         widget-move!
         set-window-title!
         set-widget-stylesheet!

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

(define (make-widget [parent #f])
  (spawn 'make-widget (lambda (p) (bezel-widget-new p)) parent))

(define (make-label text [parent #f])
  (spawn 'make-label (lambda (p) (bezel-label-new text p)) parent))

(define (make-button text [parent #f])
  (spawn 'make-button (lambda (p) (bezel-button-new text p)) parent))

(define (make-checkbox text [parent #f])
  (spawn 'make-checkbox (lambda (p) (bezel-checkbox-new text p)) parent))

(define (make-line-edit [text ""] [parent #f])
  (spawn 'make-line-edit (lambda (p) (bezel-lineedit-new text p)) parent))

(define (make-text-edit [parent #f])
  (spawn 'make-text-edit (lambda (p) (bezel-textedit-new p)) parent))

(define (make-combo [parent #f])
  (spawn 'make-combo (lambda (p) (bezel-combo-new p)) parent))

(define (make-spin-box [parent #f])
  (spawn 'make-spin-box (lambda (p) (bezel-spinbox-new p)) parent))

;; (make-slider #:vertical? #t) for a vertical slider.
(define (make-slider #:vertical? [vertical? #f] [parent #f])
  (spawn 'make-slider (lambda (p) (bezel-slider-new (if vertical? 1 0) p)) parent))

(define (make-progress [parent #f])
  (spawn 'make-progress (lambda (p) (bezel-progress-new p)) parent))

;; Named make-list-widget (not make-list) to avoid clashing with
;; racket/list's make-list.
(define (make-list-widget [parent #f])
  (spawn 'make-list-widget (lambda (p) (bezel-list-new p)) parent))

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
