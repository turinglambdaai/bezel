#lang racket/base

;; Resolution of the Bezel shim (libbezel) — the C-ABI library that the
;; Racket layer talks to through ffi/unsafe.
;;
;; Search order:
;;   1. $BEZEL_LIBRARY       — absolute path to the shared library file
;;   2. local build tree     — bezel-shim/build/ (development checkouts)
;;   3. system search paths  — ffi-lib default (LD_LIBRARY_PATH, brew, vcpkg...)
;;
;; Versioned names follow the CMake SOVERSION: libbezel.0.dylib /
;; libbezel.so.0 / bezel.dll (unversioned on Windows).

(provide bezel-lib)

(require ffi/unsafe
         racket/path
         racket/runtime-path)

(define-runtime-path here ".")

;; From bezel-lib/private/ up to the repo root (development checkouts;
;; absent for catalog installs, which use the system search paths).
(define repo-root (simplify-path (build-path here ".." "..")))

(define shim-candidates
  (for*/list ([dir (in-list (list (build-path repo-root "bezel-shim" "build")
                                  (build-path repo-root "bezel-shim" "build" "Release")))]
              [name (in-list '("libbezel.0.dylib"
                               "libbezel.dylib"
                               "libbezel.so.0"
                               "libbezel.so"
                               "bezel.dll"))])
    (build-path dir name)))

(define last-try-error #f)

(define (try-ffi path-string)
  (with-handlers ([exn:fail?
                   (lambda (e)
                     (set! last-try-error (exn-message e))
                     #f)])
    (ffi-lib path-string)))

(define (try-local-shim)
  (for/or ([p (in-list shim-candidates)])
    (and (file-exists? p) (try-ffi (path->string p)))))

(define (raise-missing!)
  (raise
   (exn:fail
    (string-append
     "bezel: cannot load the Qt shim library (libbezel)\n"
     "  Install a prebuilt shim from the releases page, or build it:\n"
     "    cmake -S bezel-shim -B bezel-shim/build -DCMAKE_BUILD_TYPE=Release\n"
     "    cmake --build bezel-shim/build\n"
     "  If the library lives elsewhere, point $BEZEL_LIBRARY at the file.\n"
     (if last-try-error
         (string-append "  last load attempt: " last-try-error "\n")
         ""))
    (current-continuation-marks))))

(define bezel-lib
  (or (let ([env (getenv "BEZEL_LIBRARY")])
        (and env (file-exists? env) (try-ffi (path->string (simple-form-path env)))))
      (try-local-shim)
      (with-handlers ([exn:fail? (lambda (_e) #f)])
        (ffi-lib '("libbezel" "bezel") '("0" "")))
      (raise-missing!)))
