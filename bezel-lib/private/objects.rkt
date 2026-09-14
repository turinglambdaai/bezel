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
         object-name
         set-object-name!
         object-set-parent!
         cstring->string/utf8
         require-alive!)

(require ffi/unsafe
         "errors.rkt"
         "raw.rkt")

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

;; Refuse to operate on dead handles up front so users get a Racket
;; error naming the call site instead of a shim error mid-flight.
(define (require-alive! who o)
  (unless (bezel-alive? o) (raise-bezel-error who)))

;; Explicit deletion: after this, the handle is dead.
(define (bezel-delete! o)
  (set-bezel-object-owned! o #f)
  (ok! 'bezel-delete! (bezel-object-delete (ptr-of o))))

;; Ownership transfer to Qt (used by layout!/set-layout after Qt
;; reparents objects); finalizer stands down.
(define (adopt-by-qt! o) (set-bezel-object-owned! o #f))

(define (object-name o)
  (require-alive! 'object-name o)
  (define p (ok-string 'object-name (bezel-object-name (ptr-of o))))
  (begin0 (cstring->string/utf8 p)
    (bezel-free p)))

(define (set-object-name! o name)
  (require-alive! 'set-object-name! o)
  (ok! 'set-object-name! (bezel-object-set-name (ptr-of o) name)))

(define (object-set-parent! o parent)
  (require-alive! 'object-set-parent! o)
  (ok! 'object-set-parent!
       (bezel-object-set-parent (ptr-of o) (and parent (ptr-of parent))))
  (adopt-by-qt! o))

;; Copy a NUL-terminated UTF-8 C string.
(define (cstring->string/utf8 p)
  (bytes->string/utf-8 (cast p _pointer _bytes)))
