#lang racket/base

(require racket/file
         racket/list
         racket/path)

(define args (vector->list (current-command-line-arguments)))
(unless (= (length args) 1)
  (raise-user-error 'verify-release-layout
                    "usage: racket scripts/verify-release-layout.rkt <runtime-root>"))

(define root (simple-form-path (car args)))
(unless (directory-exists? root)
  (error 'verify-release-layout "runtime root does not exist: ~a" root))

(define (present-any? names)
  (for/or ([name (in-list names)])
    (file-exists? (build-path root name))))

(define (require-any label names)
  (unless (present-any? names)
    (error 'verify-release-layout
           "missing ~a under ~a; expected one of ~a"
           label root names)))

(define (require-file label path)
  (unless (file-exists? path)
    (error 'verify-release-layout "missing ~a: ~a" label path)))

(case (system-type)
  [(windows)
   (for ([name (in-list '("bezel.dll"
                          "Qt6Core.dll"
                          "Qt6Gui.dll"
                          "Qt6Widgets.dll"
                          "MSVCP140.dll"
                          "VCRUNTIME140.dll"
                          "VCRUNTIME140_1.dll"))])
     (require-file name (build-path root name)))
   (require-file 'qwindows (build-path root "platforms" "qwindows.dll"))
   (require-file 'qoffscreen (build-path root "platforms" "qoffscreen.dll"))]
  [(macosx)
   (define frameworks (build-path root "BezelRuntime.app" "Contents" "Frameworks"))
   (define plugins (build-path root "BezelRuntime.app" "Contents" "PlugIns" "platforms"))
   (unless (directory-exists? frameworks)
     (error 'verify-release-layout "missing macOS Frameworks directory"))
   (unless (directory-exists? plugins)
     (error 'verify-release-layout "missing macOS platform plugin directory"))
   (unless (for/or ([name (in-list '("libbezel.0.dylib" "libbezel.dylib"))])
             (file-exists? (build-path frameworks name)))
     (error 'verify-release-layout "missing libbezel dylib in macOS app bundle"))
   (require-file 'qcocoa (build-path plugins "libqcocoa.dylib"))
   (require-file 'qoffscreen (build-path plugins "libqoffscreen.dylib"))]
  [else
   (require-any 'libbezel '("libbezel.so.0" "libbezel.so"))
   (require-any 'Qt6Core '("libQt6Core.so.6" "libQt6Core.so"))
   (require-any 'Qt6Gui '("libQt6Gui.so.6" "libQt6Gui.so"))
   (require-any 'Qt6Widgets '("libQt6Widgets.so.6" "libQt6Widgets.so"))
   (require-file 'qxcb (build-path root "platforms" "libqxcb.so"))
   (require-file 'qoffscreen (build-path root "platforms" "libqoffscreen.so"))])

(displayln "release runtime layout: OK")
