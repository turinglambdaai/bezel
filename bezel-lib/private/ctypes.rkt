#lang racket/base

;; FFI types shared by raw.rkt and the safe layer. Handles are opaque
;; pointers (the raw QObject* from the shim); the variant and signal
;; message structs mirror bezel.h exactly.

(provide (all-defined-out))

(require ffi/unsafe)

;; Opaque QObject handle.
(define _bezel-handle _pointer)

;; Struct layouts mirror bezel.h byte for byte: define-cstruct packs
;; fields without alignment padding, so the C side keeps every field
;; naturally aligned with the int8 tag last — zero padding on both
;; sides. (Field named `vt`: `tag` clashes with define-cstruct's
;; internal type-tag accessor. define-cstruct also provides the
;; _bezel-variant-pointer / _bezel-signal-msg-pointer types.)
(define BEZEL-SIGNAL-ARG-MAX 6)
(define-cstruct _bezel-variant
  ([i _int64]
   [d _double]
   [p _pointer]
   [s _pointer]
   [vt _int8]))

(define-cstruct _bezel-signal-msg
  ([conn-id _int64]
   [argv (_array _bezel-variant BEZEL-SIGNAL-ARG-MAX)]
   [argc _int]))

(define +vt-nil+ 0)
(define +vt-int+ 1)
(define +vt-double+ 2)
(define +vt-bool+ 3)
(define +vt-string+ 4)
(define +vt-object+ 5)

(define bezel-signal-arg-max BEZEL-SIGNAL-ARG-MAX)
