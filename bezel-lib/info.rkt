#lang info

(define collection "bezel")
(define deps
  '(["base" #:version "8.0"]))
(define build-deps
  '("rackunit-lib"))
(define raco-commands
  '(("bezel" bezel/cli "diagnose the Bezel native runtime" #f)))
(define pkg-desc "Qt 6 bindings for Racket — native desktop GUI with real widgets")
(define pkg-authors '(turinglambdaai))
(define license 'MIT)
(define version "0.3.0")
(define repository "https://github.com/turinglambdaai/bezel")
