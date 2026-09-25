#lang racket/base

;; The single Racket-side source of the Bezel version. scripts/
;; check-version.rkt enforces agreement with bezel-lib/info.rkt, the
;; umbrella package, the CMake shim, and the changelog. Pure data, no
;; Qt or FFI dependency, so any module (Sentry release tags, the CLI,
;; user applications) can require it freely.

(provide bezel-version)

(define bezel-version "0.3.0")
