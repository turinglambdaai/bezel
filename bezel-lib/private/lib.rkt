#lang racket/base

;; Resolution of the Bezel shim (libbezel) — the C-ABI library that the
;; Racket layer talks to through ffi/unsafe.
;;
;; Search order:
;;   1. $BEZEL_LIBRARY       — absolute path to the shared library file
;;   2. $BEZEL_NATIVE_DIR    — extracted Bezel runtime bundle directory
;;   3. package native dir   — bezel-lib/native/<os>-<arch>/
;;   4. local build tree     — bezel-shim/build/ (development checkouts)
;;   5. system search paths  — ffi-lib default (LD_LIBRARY_PATH, brew, vcpkg...)
;;
;; Versioned names follow the CMake SOVERSION: libbezel.0.dylib /
;; libbezel.so.0 / bezel.dll (unversioned on Windows).

(provide bezel-lib
         expected-bezel-abi-version
         loaded-bezel-abi-version)

(require ffi/unsafe
         racket/path
         racket/runtime-path
         "platform.rkt")

(define-runtime-path here ".")

;; From bezel-lib/private/ up to the repo root (development checkouts).
(define repo-root (simplify-path (build-path here ".." "..")))

(define shim-candidates
  (for*/list ([dir (in-list (list (build-path repo-root "bezel-shim" "build")
                                  (build-path repo-root "bezel-shim" "build" "Release")))]
              [name (in-list bezel-library-names)])
    (build-path dir name)))

(define last-try-error #f)

(define (configure-qt-plugin-path! library-path)
  ;; Respect an explicit application/operator setting. Otherwise a packaged
  ;; runtime should be fully self-contained and teach Qt where its platform
  ;; plugins live before QApplication is constructed.
  (unless (getenv "QT_PLUGIN_PATH")
    (define plugin-root (qt-plugin-root-for library-path))
    (when plugin-root
      (putenv "QT_PLUGIN_PATH" (path->string (simple-form-path plugin-root))))))

(define (try-ffi path-string [path #f])
  (with-handlers ([exn:fail?
                   (lambda (e)
                     (set! last-try-error (exn-message e))
                     #f)])
    (when path (configure-qt-plugin-path! path))
    (ffi-lib path-string)))

(define (try-path-candidates candidates)
  (for/or ([p (in-list candidates)])
    (and (file-exists? p)
         (try-ffi (path->string p) p))))

(define (raise-missing!)
  (raise
   (exn:fail
    (string-append
     "bezel: cannot load the Qt shim library (libbezel)\n"
     (format "  platform: ~a\n" bezel-platform-key)
     "  For a release runtime, extract the matching bezel-native archive and\n"
     "  point $BEZEL_NATIVE_DIR at its top-level directory.\n"
     "  For a source checkout, build the shim first:\n"
     "    cmake -S bezel-shim -B bezel-shim/build -DCMAKE_BUILD_TYPE=Release\n"
     "    cmake --build bezel-shim/build\n"
     "  You can also point $BEZEL_LIBRARY directly at the shared library.\n"
     "  Run `raco bezel doctor` for resolution diagnostics.\n"
     (if last-try-error
         (string-append "  last load attempt: " last-try-error "\n")
         ""))
    (current-continuation-marks))))

(define bezel-lib
  (or (let ([env (getenv "BEZEL_LIBRARY")])
        (and env
             (not (string=? env ""))
             (let ([p (simple-form-path env)])
               (and (file-exists? p)
                    (try-ffi (path->string p) p)))))
      (try-path-candidates bezel-native-library-candidates)
      (try-path-candidates shim-candidates)
      (with-handlers ([exn:fail?
                       (lambda (e)
                         (set! last-try-error (exn-message e))
                         #f)])
        (ffi-lib '("libbezel" "bezel") '("0" "")))
      (raise-missing!)))

;; The Racket bindings and the native shim must agree on the exact ABI.
;; Without this check, loading an incompatible libbezel can fail much
;; later as a missing symbol, wrong struct layout, or memory corruption.
(define expected-bezel-abi-version 1)

(define loaded-bezel-abi-version
  ((get-ffi-obj
    'bezel_version
    bezel-lib
    (_fun -> _int)
    (lambda ()
      (error 'bezel
             "native shim is missing bezel_version; rebuild libbezel from the same Bezel release")))))

(unless (= loaded-bezel-abi-version expected-bezel-abi-version)
  (error 'bezel
         (string-append
          "native shim ABI mismatch: Racket bindings require ABI ~a, "
          "but the loaded libbezel reports ABI ~a. "
          "Rebuild libbezel from the same Bezel release or update $BEZEL_LIBRARY.")
         expected-bezel-abi-version
         loaded-bezel-abi-version))
