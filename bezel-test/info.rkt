#lang info

(define collection "bezel-test")
(define deps '("base" "bezel-lib" "rackunit-lib"))
(define build-deps '("bezel-lib" "rackunit-lib"))
(define compile-omit-paths 'all)
(define version "0.1.0")
(define pkg-desc "Tests for Bezel — Qt 6 bindings for Racket")
(define pkg-authors '(turinglambdaai))
(define license 'MIT)
