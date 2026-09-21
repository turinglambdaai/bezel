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
;; Set BEZEL_REQUIRE_PACKAGED_RUNTIME=1 to disable steps 4-5. Release smoke
;; tests use this mode so a green job cannot accidentally borrow libbezel/Qt
;; from the runner's development environment.
;;
;; Versioned names follow the CMake SOVERSION: libbezel.0.dylib /
;; libbezel.so.0 / bezel.dll (unversioned on Windows).

(provide bezel-lib
         expected-bezel-abi-version
         loaded-bezel-abi-version
         loaded-bezel-library-path
         packaged-runtime-required?)

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

(define (truthy-env? name)
  (define value (getenv name))
  (and value
       (not (string=? value ""))
       (not (member (string-downcase value) '("0" "false" "no" "off")))))

(define packaged-runtime-required?
  (and (truthy-env? "BEZEL_REQUIRE_PACKAGED_RUNTIME") #t))

(define last-try-error #f)
(define loaded-bezel-library-path #f)

(define (configure-qt-plugin-path! library-path)
  ;; Respect an explicit application/operator setting. Otherwise a packaged
  ;; runtime should be fully self-contained and teach Qt where its platform
  ;; plugins live before QApplication is constructed.
  (unless (getenv "QT_PLUGIN_PATH")
    (define plugin-root (qt-plugin-root-for library-path))
    (when plugin-root
      (putenv "QT_PLUGIN_PATH" (path->string (simple-form-path plugin-root))))))

(define (remember-load! lib path source-description)
  (when lib
    (set! loaded-bezel-library-path
          (cond
            [path (path->string (simple-form-path path))]
            [source-description source-description]
            [else "<unknown>"])))
  lib)

(define (try-ffi path-string [path #f] [source-description #f])
  (with-handlers ([exn:fail?
                   (lambda (e)
                     (set! last-try-error (exn-message e))
                     #f)])
    (when path (configure-qt-plugin-path! path))
    (remember-load! (ffi-lib path-string) path source-description)))

(define (try-system-name name version)
  (with-handlers ([exn:fail?
                   (lambda (e)
                     (set! last-try-error (exn-message e))
                     #f)])
    (remember-load!
     (if version (ffi-lib name version) (ffi-lib name))
     #f
     (format "<system dynamic-library search: ~a>" name))))

(define (try-system-ffi)
  ;; `ffi-lib` takes one library name at a time. Trying a list as the first
  ;; argument is a contract error on supported Racket releases, so enumerate
  ;; the versioned and unversioned spellings explicitly.
  (or (try-system-name "libbezel" "0")
      (try-system-name "libbezel" #f)
      (try-system-name "bezel" "0")
      (try-system-name "bezel" #f)))

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
     (if packaged-runtime-required?
         "  hermetic mode: BEZEL_REQUIRE_PACKAGED_RUNTIME is enabled; source-build and system fallbacks are disabled.\n"
         "")
     "  For a release runtime, extract the matching bezel-native archive and\n"
     "  point $BEZEL_NATIVE_DIR at its top-level directory.\n"
     "  Self-contained release packages place the runtime under bezel/native/.\n"
     (if packaged-runtime-required?
         ""
         (string-append
          "  For a source checkout, build the shim first:\n"
          "    cmake -S bezel-shim -B bezel-shim/build -DCMAKE_BUILD_TYPE=Release\n"
          "    cmake --build bezel-shim/build\n"))
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
      (and (not packaged-runtime-required?)
           (try-path-candidates shim-candidates))
      (and (not packaged-runtime-required?)
           (try-system-ffi))
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
