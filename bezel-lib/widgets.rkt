#lang racket/base

;; Widgets: constructors and the shared widget API.
;;
;; Every constructor takes an optional parent. With a parent, Qt owns
;; the object (see private/objects.rkt); without, a Racket finalizer
;; deletes it when it becomes garbage.

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
         make-list

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

;; helper: create + wrap a widget with the standard parent/ownership rule
(define (spawn who raw-fn parent)
  (require-application)
  (wrap-handle (ok-handle who (raw-fn (and parent (ptr-of parent))))
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

(define (make-widget [parent #f]) (spawn 'make-widget bezel-widget-new parent))
(define (make-label text [parent #f])
  (require-application)
  (wrap-handle (ok-handle 'make-label (bezel-label-new text (and parent (ptr-of parent))))
               'widget (not parent)))
(define (make-button text [parent #f])
  (require-application)
  (wrap-handle (ok-handle 'make-button (bezel-button-new text (and parent (ptr-of parent))))
               'widget (not parent)))
(define (make-checkbox text [parent #f])
  (require-application)
  (wrap-handle (ok-handle 'make-checkbox (bezel-checkbox-new text (and parent (ptr-of parent))))
               'widget (not parent)))
(define (make-line-edit [text ""] [parent #f])
  (require-application)
  (wrap-handle (ok-handle 'make-line-edit (bezel-lineedit-new text (and parent (ptr-of parent))))
               'widget (not parent)))
(define (make-text-edit [parent #f]) (spawn 'make-text-edit bezel-textedit-new parent))
(define (make-combo [parent #f]) (spawn 'make-combo bezel-combo-new parent))
(define (make-spin-box [parent #f]) (spawn 'make-spin-box bezel-spinbox-new parent))

;; (make-slider #:vertical? #t) for a vertical slider.
(define (make-slider #:vertical? [vertical? #f] [parent #f])
  (require-application)
  (wrap-handle (ok-handle 'make-slider
                          (bezel-slider-new (if vertical? 1 0)
                                                (and parent (ptr-of parent))))
               'widget (not parent)))

(define (make-progress [parent #f]) (spawn 'make-progress bezel-progress-new parent))
(define (make-list [parent #f]) (spawn 'make-list bezel-list-new parent))

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

(define (widget-value w)
  (require-alive! 'widget-value w)
  (define r (bezel-widget-value (ptr-of w)))
  ;; -1 is a legitimate value for negative ranges; the shim clears its
  ;; error slot at every call, so a fresh error is the real failure signal.
  (when (and (= r -1) (last-error)) (raise-bezel-error 'widget-value))
  r)

(define (set-widget-range! w min max)
  (require-alive! 'set-widget-range! w)
  (ok! 'set-widget-range! (bezel-widget-set-range (ptr-of w) min max)))

(define (combo-add! combo item)
  (require-alive! 'combo-add! combo)
  (ok! 'combo-add! (bezel-combo-add (ptr-of combo) item)))

(define (combo-current-index combo)
  (require-alive! 'combo-current-index combo)
  (bezel-combo-current-index (ptr-of combo)))

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
  (bezel-list-current-row (ptr-of lst)))

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
  (ptr-set! len-p _int 0)
  (define data (bezel-widget-grab-png (ptr-of w) len-p))
  (unless data (raise-bezel-error 'widget-grab-png))
  (define len (ptr-ref len-p _int))
  (define bs (make-bytes len))
  (memcpy bs data len)
  (bezel-free data)
  bs)
