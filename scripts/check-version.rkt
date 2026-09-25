#lang racket/base

(require racket/file
         racket/list
         racket/path
         racket/runtime-path)

(define-runtime-path script-dir ".")
(define root (simplify-path (build-path script-dir 'up) #f))

(define (capture-version who rx path)
  (define full-path (build-path root path))
  (define text (file->string full-path))
  (define m (regexp-match rx text))
  (unless (and m (pair? (cdr m)))
    (error 'check-version "could not read ~a version from ~a" who full-path))
  (cadr m))

;; #lang info bindings are metadata consumed by Racket's setup tools; they are
;; not ordinary module exports and therefore cannot be read with dynamic-require.
;; Parse the tiny, intentionally stable version declaration instead.
(define package-version-rx
  #px"[(]define +version +\"([0-9]+[.][0-9]+[.][0-9]+)\"[)]")

(define (pkg-version relative)
  (capture-version relative
                   package-version-rx
                   (build-path relative "info.rkt")))

(define lib-version (pkg-version "bezel-lib"))
(define umbrella-version (pkg-version "bezel"))
(define shim-version
  (capture-version 'shim
                   #px"VERSION +([0-9]+[.][0-9]+[.][0-9]+)"
                   "bezel-shim/CMakeLists.txt"))
(define changelog-version
  (capture-version 'changelog
                   #px"## +([0-9]+[.][0-9]+[.][0-9]+)"
                   "CHANGELOG.md"))
(define version-module-version
  (capture-version 'version-module
                   #px"define +bezel-version +\"([0-9]+[.][0-9]+[.][0-9]+)\""
                   "bezel-lib/version.rkt"))

(define versions
  `((bezel-lib . ,lib-version)
    (bezel . ,umbrella-version)
    (bezel-shim . ,shim-version)
    (version-module . ,version-module-version)
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
  (define raw (car args))
  (define expected
    (if (and (positive? (string-length raw))
             (char=? (string-ref raw 0) #\v))
        (substring raw 1)
        raw))
  (unless (equal? lib-version expected)
    (error 'check-version
           "release tag/version mismatch: expected ~a from tag, repository is ~a"
           expected lib-version)))

(printf "version consistency: OK (~a)\n" lib-version)
