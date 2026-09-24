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
  ;; wait first: subprocess-status may otherwise report 'running
  (subprocess-wait sp)
  (define code (subprocess-status sp))
  (close-input-port stdout)
  (close-input-port stderr)
  (unless (zero? code)
    (die "raco ~a failed with exit code ~a" (string-join (map ~a args)) code)))

;; A usable runtime root contains the shim library itself — directly at
;; the root (Windows/Linux) or inside the macdeployqt BezelRuntime.app
;; bundle (macOS), matching root-library-candidates.
(define (runtime-root-usable? root)
  (for/or ([candidate (in-list (root-library-candidates root))])
    (file-exists? candidate)))

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
                      #:gui? [gui? #f]
                      #:bundle-id [bundle-id #f])
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
  ;;    (single file; `raco distribute` is avoided — it crashes when the
  ;;    embedded module graph records relative runtime paths). macOS:
  ;;    `raco distribute` output is wrapped into a proper .app bundle
  ;;    (Info.plist + Contents/MacOS) so Gatekeeper/notarization have a
  ;;    real bundle to work with. Linux: plain bin/ + lib/ layout.
  (define exe-name (if (eq? (system-type) 'windows) (~a name ".exe") (~a name)))
  (define macos? (eq? (system-type) 'macosx))
  (define contents-dir (and macos? (build-path app-dir (~a name ".app") "Contents")))
  (define distribute-dest (if contents-dir (build-path contents-dir "MacOS") app-dir))
  (define exe-path
    (cond
      [(eq? (system-type) 'windows)
       (define out (build-path app-dir exe-name))
       (run-raco! (append '("exe" "--embed-dlls" "-o")
                          (list (path->string out))
                          (if gui? '("--gui") '())
                          (list (path->string entry-path))))
       out]
      [else
       (define staging (make-temporary-file "bezel-app~a" 'directory))
       (define staged-exe (build-path staging exe-name))
       (run-raco! (append '("exe" "-o") (list (path->string staged-exe))
                          (if gui? '("--gui") '())
                          (list (path->string entry-path))))
       (unless (file-exists? staged-exe)
         (die "raco exe did not produce ~a" (path->string staged-exe)))
       ;; raco distribute creates the destination itself but not the
       ;; intermediate directories leading to it.
       (make-directory* distribute-dest)
       (run-raco! (list "distribute" (path->string distribute-dest)
                        (path->string staged-exe)))
       ;; distribute places console executables under bin/ on Unix
       (build-path distribute-dest "bin" exe-name)]))
  (unless (file-exists? exe-path)
    (die "packaging did not produce ~a" (path->string exe-path)))

  ;; 1b. The macOS bundle descriptor. bin/ + lib/ (and native/ added
  ;;     below) all live under Contents/MacOS, preserving the exe-relative
  ;;     layout distribute patched into the binary.
  (when contents-dir
    (define ident
      (or bundle-id
          (format "com.bezelapp.~a"
                  (regexp-replace* #rx"[^a-zA-Z0-9-]" (string-downcase name) "-"))))
    (printf "  bundling:      ~a.app (id ~a)\n" name ident)
    (display-to-file
     (string-append
      "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
      "<!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\""
      " \"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">\n"
      "<plist version=\"1.0\">\n<dict>\n"
      "  <key>CFBundleName</key><string>" name "</string>\n"
      "  <key>CFBundleDisplayName</key><string>" name "</string>\n"
      "  <key>CFBundleIdentifier</key><string>" ident "</string>\n"
      "  <key>CFBundleExecutable</key><string>bin/" exe-name "</string>\n"
      "  <key>CFBundlePackageType</key><string>APPL</string>\n"
      "  <key>CFBundleShortVersionString</key><string>1.0</string>\n"
      "  <key>CFBundleVersion</key><string>1.0</string>\n"
      "  <key>LSMinimumSystemVersion</key><string>11.0</string>\n"
      "  <key>NSHighResolutionCapable</key><true/>\n"
      "</dict>\n</plist>\n")
     (build-path contents-dir "Info.plist")
     #:exists 'replace))

  ;; 2. Bundle the native runtime beside the executable in exactly the
  ;;    layout private/lib.rkt resolves at startup.
  (define exe-dir (path-only exe-path))
  (define native-dest (build-path exe-dir "native" bezel-platform-key))
  (printf "  bundling:      ~a\n"
          (path->string (find-relative-path app-dir native-dest)))
  ;; copy-directory/files creates the destination itself but not the
  ;; intermediate directories leading to it.
  (make-directory* (build-path exe-dir "native"))
  (copy-directory/files runtime-root native-dest)

  ;; 3. Ship run + sign instructions next to the binary.
  (display-lines-to-file
   (list (format "To run: keep native/ beside ~a (and lib/ where present)." exe-name)
         (if macos?
             (format "        on macOS launch ~a.app (or its Contents/MacOS/bin/~a binary)." name exe-name)
             "")
         "To sign: see scripts/sign-app-windows.ps1 / scripts/sign-app-macos.sh"
         "          in the Bezel repository, and docs/APP_PACKAGING.md.")
   (build-path app-dir "RUNNING.txt")
   #:exists 'replace)

  (printf "  application:   ~a\n" (path->string (simple-form-path app-dir)))
  (printf "bezel package: done\n"))
