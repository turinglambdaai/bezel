#lang racket/base

;; Raw FFI bindings: one `bezel-` binding per function in bezel.h,
;; mechanically mapped. The safe layer (widgets.rkt & co.) wraps these
;; with error checking, string conversion, and object handles — do not
;; call raw bindings from application code.

(provide (all-defined-out))

(require (for-syntax racket/base)
         ffi/unsafe
         racket/string
         "ctypes.rkt"
         "lib.rkt"
         "marshal.rkt")

;; Custom definer: Racket kebab-case names map to C snake_case symbols
;; (bezel-widget-new -> bezel_widget_new). Every binding routes through
;; `gui` (private/marshal.rkt) so calls made from any non-GUI thread are
;; marshaled onto the Qt GUI thread. The exclusion list covers calls
;; that must run (or are safe) on the calling thread: the dispatcher's
;; queue poll, the thread-local error pair, memory release, the thread
;; check, and the liveness probe (finalizers hit it on dead handles).
(define (c-symbol id-sym)
  (string->symbol (string-replace (symbol->string id-sym) "-" "_")))

(define (make-missing id-sym)
  (lambda ()
    (error 'bezel "shim is missing C symbol ~a (is libbezel up to date?)"
           (c-symbol id-sym))))

(begin-for-syntax
  (define (unmarshaled? id-sym)
    (and (member id-sym '(bezel-next-signal
                          bezel-last-error
                          bezel-set-last-error
                          bezel-free
                          bezel-on-gui-thread
                          bezel-object-alive
                          ;; finalizers run when the pump may already be
                          ;; gone; deleteLater is safe from any thread
                          bezel-object-delete))
         #t)))

(define-syntax (define-bezel stx)
  (syntax-case stx ()
    [(_ name type)
     (if (unmarshaled? (syntax-e #'name))
         #'(define name
             (get-ffi-obj (c-symbol 'name) bezel-lib type (make-missing 'name)))
         #'(define name
             (let ([raw (get-ffi-obj (c-symbol 'name) bezel-lib type (make-missing 'name))])
               (lambda args
                 (gui (lambda () (apply raw args)))))))]))

; ---- library / memory / errors ---------------------------------------------
(define-bezel bezel-version (_fun -> _int))
(define-bezel bezel-free (_fun _pointer -> _void))
(define-bezel bezel-last-error (_fun -> _string/utf-8))
(define-bezel bezel-set-last-error (_fun _string/utf-8 -> _void))

; ---- application lifecycle ---------------------------------------------------
(define-bezel bezel-app-new (_fun _string/utf-8 -> _int))
(define-bezel bezel-app-exec (_fun -> _int))
(define-bezel bezel-app-quit (_fun _int -> _int))
(define-bezel bezel-on-gui-thread (_fun -> _int))
(define-bezel bezel-app-set-quit-on-last-window-closed (_fun _int -> _int))
(define-bezel bezel-app-quit-requested (_fun -> _int))
(define-bezel bezel-process-events (_fun _int -> _int))

; ---- objects ------------------------------------------------------------------
(define-bezel bezel-object-new (_fun -> _bezel-handle))
(define-bezel bezel-object-delete (_fun _bezel-handle -> _int))
(define-bezel bezel-object-alive (_fun _bezel-handle -> _int))
(define-bezel bezel-object-name (_fun _bezel-handle -> _pointer))
(define-bezel bezel-object-set-name (_fun _bezel-handle _string/utf-8 -> _int))
(define-bezel bezel-object-set-parent (_fun _bezel-handle _bezel-handle -> _int))

; ---- widget constructors -------------------------------------------------------
(define-bezel bezel-window-new (_fun -> _bezel-handle))
(define-bezel bezel-widget-new (_fun _bezel-handle -> _bezel-handle))
(define-bezel bezel-label-new (_fun _string/utf-8 _bezel-handle -> _bezel-handle))
(define-bezel bezel-button-new (_fun _string/utf-8 _bezel-handle -> _bezel-handle))
(define-bezel bezel-checkbox-new (_fun _string/utf-8 _bezel-handle -> _bezel-handle))
(define-bezel bezel-lineedit-new (_fun _string/utf-8 _bezel-handle -> _bezel-handle))
(define-bezel bezel-textedit-new (_fun _bezel-handle -> _bezel-handle))
(define-bezel bezel-combo-new (_fun _bezel-handle -> _bezel-handle))
(define-bezel bezel-spinbox-new (_fun _bezel-handle -> _bezel-handle))
(define-bezel bezel-slider-new (_fun _int _bezel-handle -> _bezel-handle))
(define-bezel bezel-progress-new (_fun _bezel-handle -> _bezel-handle))
(define-bezel bezel-list-new (_fun _bezel-handle -> _bezel-handle))
(define-bezel bezel-table-new (_fun _bezel-handle -> _bezel-handle))

; ---- QWidget shared API ----------------------------------------------------------
(define-bezel bezel-widget-show (_fun _bezel-handle -> _int))
(define-bezel bezel-widget-close (_fun _bezel-handle -> _int))
(define-bezel bezel-widget-hide (_fun _bezel-handle -> _int))
(define-bezel bezel-widget-set-enabled (_fun _bezel-handle _int -> _int))
(define-bezel bezel-widget-is-enabled (_fun _bezel-handle -> _int))
(define-bezel bezel-widget-resize (_fun _bezel-handle _int _int -> _int))
(define-bezel bezel-widget-move (_fun _bezel-handle _int _int -> _int))
(define-bezel bezel-window-set-title (_fun _bezel-handle _string/utf-8 -> _int))
(define-bezel bezel-widget-set-stylesheet (_fun _bezel-handle _string/utf-8 -> _int))
;; (handle, int* len_out) -> PNG bytes pointer (caller frees via bezel-free).
(define-bezel bezel-widget-grab-png
  (_fun _bezel-handle _pointer -> _pointer))
(define-bezel bezel-widget-set-tooltip (_fun _bezel-handle _string/utf-8 -> _int))
(define-bezel bezel-widget-tooltip (_fun _bezel-handle -> _pointer))
(define-bezel bezel-widget-width (_fun _bezel-handle -> _int))
(define-bezel bezel-widget-height (_fun _bezel-handle -> _int))
(define-bezel bezel-widget-x (_fun _bezel-handle -> _int))
(define-bezel bezel-widget-y (_fun _bezel-handle -> _int))
(define-bezel bezel-widget-center (_fun _bezel-handle -> _int))

; ---- value API --------------------------------------------------------------------
(define-bezel bezel-widget-set-text (_fun _bezel-handle _string/utf-8 -> _int))
(define-bezel bezel-widget-text (_fun _bezel-handle -> _pointer))
(define-bezel bezel-widget-set-checked (_fun _bezel-handle _int -> _int))
(define-bezel bezel-widget-is-checked (_fun _bezel-handle -> _int))
(define-bezel bezel-widget-set-value (_fun _bezel-handle _int -> _int))
(define-bezel bezel-widget-value (_fun _bezel-handle -> _int))
(define-bezel bezel-widget-set-range (_fun _bezel-handle _int _int -> _int))
(define-bezel bezel-combo-add (_fun _bezel-handle _string/utf-8 -> _int))
(define-bezel bezel-combo-current-index (_fun _bezel-handle -> _int))
(define-bezel bezel-combo-set-index (_fun _bezel-handle _int -> _int))
(define-bezel bezel-combo-current-text (_fun _bezel-handle -> _pointer))
(define-bezel bezel-list-add (_fun _bezel-handle _string/utf-8 -> _int))
(define-bezel bezel-list-current-row (_fun _bezel-handle -> _int))
(define-bezel bezel-list-set-current-row (_fun _bezel-handle _int -> _int))
(define-bezel bezel-list-current-text (_fun _bezel-handle -> _pointer))
(define-bezel bezel-widget-set-placeholder (_fun _bezel-handle _string/utf-8 -> _int))
(define-bezel bezel-widget-set-readonly (_fun _bezel-handle _int -> _int))
(define-bezel bezel-table-set-dimensions (_fun _bezel-handle _int _int -> _int))
(define-bezel bezel-table-row-count (_fun _bezel-handle -> _int))
(define-bezel bezel-table-column-count (_fun _bezel-handle -> _int))
(define-bezel bezel-table-set-header-labels (_fun _bezel-handle _string/utf-8 -> _int))
(define-bezel bezel-table-set-cell-text (_fun _bezel-handle _int _int _string/utf-8 -> _int))
(define-bezel bezel-table-cell-text (_fun _bezel-handle _int _int -> _pointer))

; ---- layouts ------------------------------------------------------------------------
(define-bezel bezel-vbox-new (_fun -> _bezel-handle))
(define-bezel bezel-hbox-new (_fun -> _bezel-handle))
(define-bezel bezel-grid-new (_fun -> _bezel-handle))
(define-bezel bezel-form-new (_fun -> _bezel-handle))
(define-bezel bezel-widget-set-layout (_fun _bezel-handle _bezel-handle -> _int))
;; QMainWindow needs a central widget rather than a direct setLayout.
(define-bezel bezel-window-central-layout (_fun _bezel-handle _bezel-handle -> _int))
(define-bezel bezel-layout-add-widget (_fun _bezel-handle _bezel-handle _int -> _int))
(define-bezel bezel-layout-add-layout (_fun _bezel-handle _bezel-handle _int -> _int))
(define-bezel bezel-layout-add-stretch (_fun _bezel-handle _int -> _int))
(define-bezel bezel-layout-set-spacing (_fun _bezel-handle _int -> _int))
(define-bezel bezel-layout-set-margins (_fun _bezel-handle _int _int _int _int -> _int))
(define-bezel bezel-grid-add (_fun _bezel-handle _bezel-handle _int _int _int _int -> _int))
(define-bezel bezel-form-add-row (_fun _bezel-handle _string/utf-8 _bezel-handle -> _int))

; ---- menus ---------------------------------------------------------------------------
(define-bezel bezel-menubar (_fun _bezel-handle -> _bezel-handle))
(define-bezel bezel-menu-add (_fun _bezel-handle _string/utf-8 -> _bezel-handle))
(define-bezel bezel-menu-action (_fun _bezel-handle _string/utf-8 -> _bezel-handle))
(define-bezel bezel-menu-separator (_fun _bezel-handle -> _bezel-handle))
(define-bezel bezel-action-set-shortcut (_fun _bezel-handle _string/utf-8 -> _int))

; ---- dialogs ----------------------------------------------------------------------------
(define-bezel bezel-msg-information (_fun _bezel-handle _string/utf-8 _string/utf-8 -> _int))
(define-bezel bezel-msg-warning (_fun _bezel-handle _string/utf-8 _string/utf-8 -> _int))
(define-bezel bezel-msg-question (_fun _bezel-handle _string/utf-8 _string/utf-8 -> _int))
(define-bezel bezel-get-open-file-name
  (_fun _bezel-handle _string/utf-8 _string/utf-8 _string/utf-8 -> _pointer))
(define-bezel bezel-get-save-file-name
  (_fun _bezel-handle _string/utf-8 _string/utf-8 _string/utf-8 -> _pointer))

; ---- signals --------------------------------------------------------------------------------
(define-bezel bezel-connect (_fun _bezel-handle _string/utf-8 -> _int64))
(define-bezel bezel-disconnect (_fun _bezel-handle _int64 -> _int))
;; Pointers are to a caller-allocated _bezel-signal-msg (next-signal) or
;; an array of _bezel-variant (signal-emit).
(define-bezel bezel-next-signal (_fun _int _pointer -> _int))
(define-bezel bezel-signal-emit
  (_fun _bezel-handle _string/utf-8 _int _pointer -> _int))

; ---- shutdown ---------------------------------------------------------------------------------
(define-bezel bezel-cleanup (_fun -> _int))
