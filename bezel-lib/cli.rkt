#lang racket/base

(require racket/format
         racket/list
         racket/match
         racket/path
         racket/string
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

;; ---- raco bezel package -----------------------------------------------------
;;
;; Build a self-contained application folder from an entry module:
;; embedded executable + bundled native runtime. See private/pack.rkt.

(define package-usage
  (string-append
   "usage: raco bezel package --entry <module.rkt> --name <AppName>\n"
   "                      [--dest <dir>] [--runtime-dir <dir>] [--gui]\n"))

(define (flag->key flag)
  (match flag
    ["--entry" 'entry]
    ["--name" 'name]
    ["--dest" 'dest]
    ["--runtime-dir" 'runtime-dir]
    ["--gui" 'gui]
    [_ #f]))

;; Boolean flags carry no value.
(define boolean-flags '(gui))

(define (parse-package-flags args)
  (let loop ([args args] [flags '()])
    (match args
      [(list) (reverse flags)]
      [(list flag value rest ...)
       (define key (flag->key flag))
       (cond
         [(memq key boolean-flags) (loop (cons value rest) (cons (cons key #t) flags))]
         [key (loop rest (cons (cons key value) flags))]
         [else (raise-user-error 'bezel/package "unknown flag: ~a\n~a" flag package-usage)])]
      [(list flag)
       (define key (flag->key flag))
       (cond
         [(memq key boolean-flags) (reverse (cons (cons key #t) flags))]
         [key (raise-user-error 'bezel/package "flag ~a needs a value\n~a" flag package-usage)]
         [else (raise-user-error 'bezel/package "unknown flag: ~a\n~a" flag package-usage)])]
      [_ (raise-user-error 'bezel/package package-usage)])))

(define (flag-ref flags key [default #f])
  (cond [(assq key flags) => cdr] [else default]))

(define (package-command args)
  (unless (pair? args)
    (raise-user-error 'bezel/package package-usage))
  (define flags (parse-package-flags args))
  (define entry (flag-ref flags 'entry))
  (define name (flag-ref flags 'name))
  (unless entry (raise-user-error 'bezel/package "--entry is required\n~a" package-usage))
  (unless name (raise-user-error 'bezel/package "--name is required\n~a" package-usage))
  ((dynamic-require 'bezel/private/pack 'package-app!)
   #:entry entry
   #:name name
   #:dest (flag-ref flags 'dest "dist")
   #:runtime-dir (and (flag-ref flags 'runtime-dir)
                      (path->complete-path (flag-ref flags 'runtime-dir)))
   #:gui? (and (flag-ref flags 'gui) #t)))

(define args (vector->list (current-command-line-arguments)))
(cond
  [(or (null? args) (equal? args '("doctor")))
   (doctor)]
  [(equal? (car args) "package")
   (package-command (cdr args))]
  [else
   (eprintf "usage: raco bezel [doctor | package ...]\n")
   (exit 2)])
