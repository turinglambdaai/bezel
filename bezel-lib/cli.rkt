#lang racket/base

(require racket/format
         racket/list
         racket/path
         "private/platform.rkt")

(define (env-display name)
  (define v (getenv name))
  (if (and v (not (string=? v ""))) v "<not set>"))

(define (candidate-state p)
  (if (file-exists? p) "found" "missing"))

(define (doctor)
  (displayln "Bezel native runtime diagnostics")
  (displayln (format "  Racket:        ~a" (version)))
  (displayln (format "  OS:            ~a" (system-type 'os*)))
  (displayln (format "  architecture:  ~a" (system-type 'arch)))
  (displayln (format "  runtime key:   ~a" bezel-platform-key))
  (displayln (format "  BEZEL_LIBRARY: ~a" (env-display "BEZEL_LIBRARY")))
  (displayln (format "  BEZEL_NATIVE_DIR: ~a" (env-display "BEZEL_NATIVE_DIR")))
  (displayln (format "  BEZEL_REQUIRE_PACKAGED_RUNTIME: ~a"
                     (env-display "BEZEL_REQUIRE_PACKAGED_RUNTIME")))
  (displayln (format "  QT_PLUGIN_PATH:   ~a" (env-display "QT_PLUGIN_PATH")))
  (displayln "  native candidates:")
  (if (null? bezel-native-library-candidates)
      (displayln "    <none>")
      (for ([p (in-list bezel-native-library-candidates)])
        (displayln (format "    [~a] ~a" (candidate-state p) (path->string p)))))
  (display "  load test:     ")
  (flush-output)
  (with-handlers ([exn:fail?
                   (lambda (e)
                     (displayln "FAILED")
                     (displayln (format "    ~a" (exn-message e)))
                     (exit 1))])
    (define abi (dynamic-require 'bezel/private/lib 'loaded-bezel-abi-version))
    (define loaded-path (dynamic-require 'bezel/private/lib 'loaded-bezel-library-path))
    (define strict? (dynamic-require 'bezel/private/lib 'packaged-runtime-required?))
    (displayln (format "OK (ABI ~a)" abi))
    (displayln (format "  selected shim: ~a" loaded-path))
    (displayln (format "  hermetic packaged-runtime mode: ~a" (if strict? "enabled" "disabled")))))

(define args (vector->list (current-command-line-arguments)))
(cond
  [(or (null? args) (equal? args '("doctor")))
   (doctor)]
  [else
   (eprintf "usage: raco bezel [doctor]\n")
   (exit 2)])
