#lang racket/base

(require file/sha1
         racket/file
         racket/path
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
(define version (dynamic-require (build-path source-package "info.rkt") 'version))

(make-directory* output-dir)

(define staging-root (make-temporary-file "bezel-package~a" 'directory))
(define staging-package (build-path staging-root "bezel-lib"))
(define native-dest (build-path staging-package "native" platform-key))
(define raco (find-executable-path "raco"))

(unless raco
  (raise-user-error 'package-racket-runtime "raco was not found on PATH"))

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

   (define final
     (build-path output-dir
                 (format "bezel-lib-~a-~a.zip" version platform-key)))
   (when (file-exists? final) (delete-file final))
   (rename-file-or-directory created final)

   ;; Racket package servers conventionally publish a neighboring .CHECKSUM
   ;; containing the SHA-1 of the archive. Keep that convention even though the
   ;; GitHub Release also publishes modern SHA-256 checksums for users/tools.
   (define checksum
     (call-with-input-file final sha1 #:mode 'binary))
   (define checksum-path
     (string->path (string-append (path->string final) ".CHECKSUM")))
   (call-with-output-file checksum-path
     #:exists 'truncate/replace
     (lambda (out)
       (display checksum out)
       (newline out)))

   (displayln (path->string final))
   (displayln (path->string checksum-path)))
 (lambda ()
   (when (directory-exists? staging-root)
     (delete-directory/files staging-root))))
