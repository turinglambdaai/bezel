#lang racket/base

(provide bezel-platform-key
         bezel-library-names
         bezel-native-search-roots
         bezel-native-library-candidates
         qt-plugin-root-for
         bezel-lib-root)

(require racket/list
         racket/path)

;; Keep the key deliberately boring and stable: release assets, package-local
;; bundles, diagnostics, and CI all use the same <os>-<arch> spelling.
(define bezel-platform-key
  (format "~a-~a" (system-type 'os*) (system-type 'arch)))

(define bezel-library-names
  (case (system-type)
    [(windows) '("bezel.dll")]
    [(macosx) '("libbezel.0.dylib" "libbezel.dylib")]
    [else '("libbezel.so.0" "libbezel.so")]))

;; Root of the installed `bezel` collection (the bezel-lib package
;; directory). Deliberately NOT define-runtime-path: relative runtime-path
;; specs (".." / ".") are serialized into `raco exe` binaries as 'up/'same,
;; and `raco distribute` crashes on them (split-path contract violation).
;; In a standalone executable the collection may not resolve at all, so
;; the lookup is guarded and callers treat #f as "no package-local
;; runtime here".
(define bezel-lib-root
  (with-handlers ([exn:fail? (lambda (e) #f)])
    (collection-path "bezel")))

(define (directory-env name)
  (define value (getenv name))
  (and value
       (not (string=? value ""))
       (simple-form-path value)))

;; Directory of the running executable. For a `raco exe` distribution
;; this is the shipped application folder, so <exe-dir>/native/<os>-<arch>
;; is how packaged applications find their bundled runtime. During
;; ordinary development it is the Racket installation directory, where
;; no native/ bundle exists — a harmless extra candidate.
(define (executable-directory)
  (define exe (find-executable-path (find-system-path 'exec-file)))
  (and exe (path-only exe)))

(define bezel-native-search-roots
  (filter values
          (list (directory-env "BEZEL_NATIVE_DIR")
                (and bezel-lib-root
                     (build-path bezel-lib-root "native" bezel-platform-key))
                (and (executable-directory)
                     (build-path (executable-directory) "native" bezel-platform-key)))))

(define (root-library-candidates root)
  (append
   (for/list ([name (in-list bezel-library-names)])
     (build-path root name))
   ;; macdeployqt naturally produces a self-contained .app. Keep that bundle
   ;; intact so its Frameworks/PlugIns layout remains valid and let Racket load
   ;; libbezel directly from the deployed Frameworks directory.
   (if (eq? (system-type) 'macosx)
       (for/list ([name (in-list bezel-library-names)])
         (build-path root "BezelRuntime.app" "Contents" "Frameworks" name))
       '())))

(define bezel-native-library-candidates
  (append-map root-library-candidates bezel-native-search-roots))

(define (qt-plugin-root-for library-path)
  (define lib-dir (path-only library-path))
  (cond
    [(not lib-dir) #f]
    ;; Windows/Linux release layout: platform plugins live at
    ;; <runtime-root>/platforms, so QT_PLUGIN_PATH points at runtime-root.
    [(directory-exists? (build-path lib-dir "platforms")) lib-dir]
    ;; Alternate layout accepted for hand-built bundles.
    [(directory-exists? (build-path lib-dir "plugins" "platforms"))
     (build-path lib-dir "plugins")]
    ;; macdeployqt layout: libbezel is in Contents/Frameworks while plugins are
    ;; in Contents/PlugIns.
    [else
     (define contents-dir (simplify-path (build-path lib-dir 'up) #f))
     (define plugins-dir (build-path contents-dir "PlugIns"))
     (and (directory-exists? (build-path plugins-dir "platforms"))
          plugins-dir)]))
