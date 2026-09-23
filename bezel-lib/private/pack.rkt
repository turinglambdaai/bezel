#lang racket/base

;; Final-application packaging: turn a Racket entry module plus a Bezel
;; native runtime into a self-contained, redistributable application
;; folder.
;;
;;   raco bezel package --entry my-app.rkt --name MyApp --dest dist
;;
;; Layout produced (the exe-relative runtime step in private/lib.rkt
;; resolves it at startup):
;;
;;   dist/MyApp/
;;     MyApp[.exe]                  standalone launcher
;;     lib/...                      Racket runtime (macOS/Linux;
;;                                   Windows embeds the DLLs in the exe)
;;     native/<os>-<arch>/...       libbezel + Qt + plugins
;;
;; Runtime source priority: --runtime-dir argument, $BEZEL_NATIVE_DIR,
;; the installed bezel-lib package's own bundled runtime.

(provide package-app!)

(require racket/file
         racket/format
         racket/list
         racket/path
         racket/port
         racket/string
         "platform.rkt")

(define (find-raco)
  (or (find-executable-path "raco")
      (find-executable-path "raco.exe")
      (raise-user-error 'bezel/package "raco was not found on PATH")))

(define (die fmt . args)
  (raise-user-error 'bezel/package "~a" (apply format fmt args)))

(define (run-raco! args)
  (define raco (find-raco))
  (printf "  $ raco ~a\n" (string-join (map ~a args) " "))
  (define-values (sp stdout stdin stderr)
    (apply subprocess #f #f #f raco args))
  (close-output-port stdin)
  (copy-port stdout (current-output-port))
  (copy-port stderr (current-error-port))
  (define code (subprocess-status sp))
  (close-input-port stdout)
  (close-input-port stderr)
  (subprocess-wait sp)
  (unless (zero? code)
    (die "raco ~a failed with exit code ~a" (string-join (map ~a args)) code)))

;; A usable runtime root contains the shim library itself.
(define (runtime-root-usable? root)
  (for/or ([name (in-list bezel-library-names)])
    (file-exists? (build-path root name))))

(define (resolve-runtime-dir explicit)
  (or explicit
      (for/or ([root (in-list bezel-native-search-roots)]
               #:when (and (directory-exists? root) (runtime-root-usable? root)))
        root)
      (die
       (string-append
        "no Bezel native runtime found.\n"
        "  Pass --runtime-dir pointing at an extracted bezel-native-* archive,\n"
        "  set $BEZEL_NATIVE_DIR, or install a self-contained bezel-lib package\n"
        "  (bezel-lib-<platform>.zip from the GitHub Release)."))))

(define (package-app! #:entry entry
                      #:name name
                      #:dest [dest "dist"]
                      #:runtime-dir [runtime-dir #f]
                      #:gui? [gui? #f])
  (define entry-path (path->complete-path entry))
  (unless (file-exists? entry-path)
    (die "entry module does not exist: ~a" (path->string entry-path)))
  (unless (non-empty-string? name)
    (die "application name must be a non-empty string"))

  (define runtime-root (simple-form-path (resolve-runtime-dir runtime-dir)))
  (printf "bezel package: ~a\n" name)
  (printf "  entry:         ~a\n" (path->string entry-path))
  (printf "  runtime:       ~a\n" (path->string runtime-root))

  (define app-dir (build-path (path->complete-path dest) name))
  (when (directory-exists? app-dir)
    (delete-directory/files app-dir))
  (make-directory* app-dir)

  ;; 1. Standalone launcher with no Racket installation required.
  ;;    Windows: --embed-dlls puts the Racket runtime inside the exe
  ;;    (single file; `raco distribute` is avoided — it breaks on
  ;;    current Racket builds). macOS/Linux: `raco distribute` places
  ;;    the exe together with a lib/ tree of Racket runtime libraries.
  (define exe-name (if (eq? (system-type) 'windows) (~a name ".exe") (~a name)))
  (cond
    [(eq? (system-type) 'windows)
     (run-raco! (append '("exe" "--embed-dlls" "-o")
                        (list (path->string (build-path app-dir exe-name)))
                        (if gui? '("--gui") '())
                        (list (path->string entry-path))))]
    [else
     (define staging (make-temporary-file "bezel-app~a" 'directory))
     (define staged-exe (build-path staging exe-name))
     (run-raco! (append '("exe" "-o") (list (path->string staged-exe))
                        (if gui? '("--gui") '())
                        (list (path->string entry-path))))
     (unless (file-exists? staged-exe)
       (die "raco exe did not produce ~a" (path->string staged-exe)))
     (run-raco! (list "distribute" (path->string app-dir) (path->string staged-exe)))])
  (unless (file-exists? (build-path app-dir exe-name))
    (die "packaging did not produce ~a" (path->string (build-path app-dir exe-name))))

  ;; 2. Bundle the native runtime beside the executable in exactly the
  ;;    layout private/lib.rkt resolves at startup.
  (define native-dest (build-path app-dir "native" bezel-platform-key))
  (printf "  bundling:      native/~a\n" bezel-platform-key)
  ;; copy-directory/files creates the destination itself but not the
  ;; intermediate directories leading to it.
  (make-directory* (build-path app-dir "native"))
  (copy-directory/files runtime-root native-dest)

  ;; 3. Ship run + sign instructions next to the binary.
  (display-lines-to-file
   (list (format "To run: keep native/ beside ~a (and lib/ where present)." exe-name)
         "To sign: see scripts/sign-app-windows.ps1 / scripts/sign-app-macos.sh"
         "          in the Bezel repository, and docs/APP_PACKAGING.md.")
   (build-path app-dir "RUNNING.txt")
   #:exists 'replace)

  (printf "  application:   ~a\n" (path->string (simple-form-path app-dir)))
  (printf "bezel package: done\n"))
