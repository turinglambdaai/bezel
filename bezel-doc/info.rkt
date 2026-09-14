#lang info

(define collection "bezel-doc")
(define deps '("base" "bezel-lib" "scribble-lib" "racket-doc"))
(define build-deps '("bezel-lib" "scribble-lib" "racket-doc" "rackunit-lib"))
(define scribblings '(("bezel.scrbl" ())))
(define version "0.1.0")
(define pkg-desc "Documentation for Bezel — Qt 6 bindings for Racket")
(define pkg-authors '(turinglambdaai))
(define license 'MIT)
