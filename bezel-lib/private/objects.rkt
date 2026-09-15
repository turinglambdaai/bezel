#lang racket/base

;; The object model of the safe layer: every Qt object Racket holds is
;; a `bezel-object` wrapping the raw handle, a kind tag, and an
;; ownership flag.
;;
;; Ownership follows Qt's parent rule:
;;   - created WITHOUT a parent  -> Racket owns it; a finalizer calls
;;     bezel_object_delete (deleteLater) when the value becomes garbage
;;   - created WITH a parent, or attached to a layout/window afterwards
;;     -> Qt owns it; `owned` flips to #f and the finalizer stands down
;;
;; Handles may outlive their Qt object (user closed a window, parent
;; chain deleted it). Use `bezel-alive?` to check; calls on dead handles
;; raise exn:fail:bezel.

(provide (struct-out bezel-object)
         wrap-handle
         ptr-of
         bezel-alive?
         bezel-delete!
         adopt-by-qt!
         qt-object-name
         set-qt-object-name!
         object-set-parent!
         cstring->string/utf8
         require-alive!)

(require ffi/unsafe
         "errors.rkt"
         "raw.rkt")

;; (re-exported via errors.rkt users; exn:fail:bezel comes from errors)

;; kind is one of 'widget 'layout 'menu 'action 'object 'application;
;; the layout tree builder uses it to pick add-widget vs add-layout.
(struct bezel-object (ptr kind [owned #:mutable]) #:transparent)

(define (wrap-handle ptr kind owned)
  (define o (bezel-object ptr kind owned))
  (when owned
    (register-finalizer
     o
     (lambda (obj)
       ;; The shim no-ops safely when the object is already gone; the
       ;; deleteLater form is safe even at teardown.
       (bezel-object-delete (bezel-object-ptr obj))
       (void))))
  o)

(define (ptr-of o) (bezel-object-ptr o))

(define (bezel-alive? o)
  (= 1 (bezel-object-alive (ptr-of o))))

;; Refuse to operate on dead handles up front. bezel_object_alive does
;; not set shim errors (finalizers call it on dead handles routinely),
;; so the message here is built locally — "unknown error" would be
;; misleading.
(define (require-alive! who o)
  (unless (bezel-alive? o)
    (raise
     (exn:fail:bezel
      (format "bezel: ~a: the Qt object behind this handle has been destroyed" who)
      (current-continuation-marks)))))

;; Explicit deletion: after this, the handle is dead.
(define (bezel-delete! o)
  (set-bezel-object-owned! o #f)
  (ok! 'bezel-delete! (bezel-object-delete (ptr-of o))))

;; Ownership transfer to Qt (used by layout!/set-layout after Qt
;; reparents objects); finalizer stands down.
(define (adopt-by-qt! o) (set-bezel-object-owned! o #f))

;; Named qt-object-name (not object-name) to avoid clashing with
;; racket/base's object-name for procedures.
(define (qt-object-name o)
  (require-alive! 'qt-object-name o)
  (define p (ok-string 'qt-object-name (bezel-object-name (ptr-of o))))
  (begin0 (cstring->string/utf8 p)
    (bezel-free p)))

(define (set-qt-object-name! o name)
  (require-alive! 'set-qt-object-name! o)
  (ok! 'set-qt-object-name! (bezel-object-set-name (ptr-of o) name)))

(define (object-set-parent! o parent)
  (require-alive! 'object-set-parent! o)
  (ok! 'object-set-parent!
       (bezel-object-set-parent (ptr-of o) (and parent (ptr-of parent))))
  (adopt-by-qt! o))

;; Copy a NUL-terminated UTF-8 C string.
(define (cstring->string/utf8 p)
  (bytes->string/utf-8 (cast p _pointer _bytes)))
