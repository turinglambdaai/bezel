#lang racket/base

(require file/sha1
         racket/file
         racket/path
         racket/runtime-path
         racket/system)

(define args (vector->list (current-command-line-arguments)))
(unless (= (length args) 3)
  (raise-user-error
   'package-racket-runtime
   "usage: racket scripts/package-racket-runtime.rkt <runtime-root> <platform-key> <output-dir>"))

(define runtime-root (simple-form-path (car args)))
(define platform-key (cadr args))
(define output-dir (simple-form-path (caddr args)))

(unless (directory-exists? runtime-root)
  (raise-user-error 'package-racket-runtime
                    "runtime root does not exist: ~a"
                    (path->string runtime-root)))

(define-runtime-path script-dir ".")
(define repo-root (simplify-path (build-path script-dir 'up) #f))
(define source-package (build-path repo-root "bezel-lib"))
(define verify-layout (build-path script-dir "verify-release-layout.rkt"))

(make-directory* output-dir)

(define staging-root (make-temporary-file "bezel-package~a" 'directory))
(define staging-package (build-path staging-root "bezel-lib"))
(define native-dest (build-path staging-package "native" platform-key))
(define racket-exe (find-executable-path "racket"))
(define raco (find-executable-path "raco"))

(unless racket-exe
  (raise-user-error 'package-racket-runtime "racket was not found on PATH"))
(unless raco
  (raise-user-error 'package-racket-runtime "raco was not found on PATH"))

;; Fail before producing a package if a packager forgot a core Qt library or
;; either the real desktop QPA backend or the offscreen backend used by CI.
(unless (system* racket-exe
                 (path->string verify-layout)
                 (path->string runtime-root))
  (error 'package-racket-runtime "native runtime layout validation failed"))

(dynamic-wind
 void
 (lambda ()
   (copy-directory/files source-package staging-package)
   (make-directory* (path-only native-dest))
   (copy-directory/files runtime-root native-dest)

   (unless (system* raco
                    "pkg" "create"
                    "--format" "zip"
                    "--as-is"
                    "--dest" (path->string output-dir)
                    (path->string staging-package))
     (error 'package-racket-runtime "raco pkg create failed"))

   (define created (build-path output-dir "bezel-lib.zip"))
   (unless (file-exists? created)
     (error 'package-racket-runtime
            "raco pkg create did not produce expected archive: ~a"
            (path->string created)))

   ;; The GitHub release tag already carries the semantic version, so keep the
   ;; asset name stable across versions. That lets CI and install instructions
   ;; stay data-driven instead of duplicating the version in workflow YAML.
   (define final
     (build-path output-dir
                 (format "bezel-lib-~a.zip" platform-key)))
   (when (file-exists? final) (delete-file final))
   (rename-file-or-directory created final)

   ;; Racket treats a neighboring .CHECKSUM file as the exact expected SHA-1
   ;; string. Do not append a newline: it becomes part of the expected checksum
   ;; and makes an otherwise valid local archive fail installation.
   (define checksum
     (call-with-input-file final sha1 #:mode 'binary))
   (define checksum-path
     (string->path (string-append (path->string final) ".CHECKSUM")))
   (call-with-output-file checksum-path
     #:exists 'truncate/replace
     (lambda (out)
       (display checksum out)))

   (displayln (path->string final))
   (displayln (path->string checksum-path)))
 (lambda ()
   (when (directory-exists? staging-root)
     (delete-directory/files staging-root))))
