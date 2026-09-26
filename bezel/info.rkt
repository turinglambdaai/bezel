#lang info

(define collection 'multi)

(define deps
  '(["base" #:version "8.0"]
    "bezel-lib"))
(define build-deps
  '("bezel-lib"))
(define implies
  '("bezel-lib"))

(define version "0.3.0")
(define pkg-desc "Qt 6 bindings for Racket — native desktop GUI with real widgets")
(define pkg-authors '(turinglambdaai))
(define license 'MIT)
(define repository "https://github.com/turinglambdaai/bezel")
