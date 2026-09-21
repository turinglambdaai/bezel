#lang racket/base

(require racket/file
         racket/list
         racket/path
         racket/string)

(define-runtime-path script-dir ".")
(define root (simplify-path (build-path script-dir 'up) #f))

(define (pkg-version relative)
  (dynamic-require (build-path root relative "info.rkt") 'version))

(define (capture-version who rx path)
  (define text (file->string (build-path root path)))
  (define m (regexp-match rx text))
  (unless (and m (pair? (cdr m)))
    (error 'check-version "could not read ~a version from ~a" who path))
  (cadr m))

(define lib-version (pkg-version "bezel-lib"))
(define umbrella-version (pkg-version "bezel"))
(define shim-version
  (capture-version 'shim
                   #px"VERSION[ \\t]+([0-9]+\\.[0-9]+\\.[0-9]+)"
                   "bezel-shim/CMakeLists.txt"))
(define changelog-version
  (capture-version 'changelog
                   #px"##[ \\t]+([0-9]+\\.[0-9]+\\.[0-9]+)"
                   "CHANGELOG.md"))

(define versions
  `((bezel-lib . ,lib-version)
    (bezel . ,umbrella-version)
    (bezel-shim . ,shim-version)
    (changelog . ,changelog-version)))

(for ([entry (in-list versions)])
  (printf "~a: ~a\n" (car entry) (cdr entry)))

(for ([entry (in-list (cdr versions))])
  (unless (equal? lib-version (cdr entry))
    (error 'check-version
           "version mismatch: bezel-lib is ~a but ~a is ~a"
           lib-version (car entry) (cdr entry))))

(define args (vector->list (current-command-line-arguments)))
(unless (or (null? args) (= (length args) 1))
  (raise-user-error 'check-version "usage: racket scripts/check-version.rkt [expected-version]"))

(when (pair? args)
  (define expected (string-trim (car args) "v" #:left? #t #:right? #f))
  (unless (equal? lib-version expected)
    (error 'check-version
           "release tag/version mismatch: expected ~a from tag, repository is ~a"
           expected lib-version)))

(printf "version consistency: OK (~a)\n" lib-version)
