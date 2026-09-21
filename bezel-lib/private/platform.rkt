#lang racket/base

(provide bezel-platform-key
         bezel-library-names
         bezel-native-search-roots
         bezel-native-library-candidates
         qt-plugin-root-for)

(require racket/list
         racket/path
         racket/runtime-path)

;; Keep the key deliberately boring and stable: release assets, package-local
;; bundles, diagnostics, and CI all use the same <os>-<arch> spelling.
(define bezel-platform-key
  (format "~a-~a" (system-type 'os*) (system-type 'arch)))

(define bezel-library-names
  (case (system-type)
    [(windows) '("bezel.dll")]
    [(macosx) '("libbezel.0.dylib" "libbezel.dylib")]
    [else '("libbezel.so.0" "libbezel.so")]))

(define-runtime-path bezel-lib-root "..")

(define (directory-env name)
  (define value (getenv name))
  (and value
       (not (string=? value ""))
       (simple-form-path value)))

(define bezel-native-search-roots
  (filter values
          (list (directory-env "BEZEL_NATIVE_DIR")
                (build-path bezel-lib-root "native" bezel-platform-key))))

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
     (define contents-dir (and (path-only lib-dir) (path-only (path-only lib-dir))))
     (define plugins-dir (and contents-dir (build-path contents-dir "PlugIns")))
     (and plugins-dir
          (directory-exists? (build-path plugins-dir "platforms"))
          plugins-dir)]))
