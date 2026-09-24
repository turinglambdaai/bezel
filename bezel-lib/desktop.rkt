#lang racket/base

;; Desktop integration: the system clipboard and the system tray.
;;
;;   (clipboard-set-text! (format "~a" result))
;;   (clipboard-text)
;;
;;   (define tray (make-tray "app.png" "MyApp"))
;;   (tray-set-menu! tray (menu! (menu-bar win) "Tray"))
;;   (tray-show! tray)
;;   (tray-notify! tray "Export finished" "results.csv written" #:icon 'information)
;;
;; The tray icon path is loaded by QIcon; an empty path may render
;; nothing on some platforms, so pass a real file for production.
;; Tray signals ("activated(QSystemTrayIcon::ActivationReason)",
;; "messageClicked()") deliver argless through the signal bridge.

(provide clipboard-set-text!
         clipboard-text
         make-tray
         set-tray-tooltip!
         tray-show!
         tray-hide!
         tray-notify!
         tray-set-menu!)

(require "private/errors.rkt"
         "private/objects.rkt"
         "private/raw.rkt")

;; ---- clipboard ---------------------------------------------------------------

(define (clipboard-set-text! text)
  (require-application)
  (ok! 'clipboard-set-text! (bezel-clipboard-set-text text)))

(define (clipboard-text)
  (require-application)
  (define p (ok-string 'clipboard-text (bezel-clipboard-text)))
  (begin0 (cstring->string/utf8 p)
    (bezel-free p)))

;; ---- system tray ---------------------------------------------------------------

;; (make-tray icon-path tooltip) — the icon is not shown until tray-show!.
(define (make-tray [icon-path ""] [tooltip ""])
  (require-application)
  (wrap-handle (ok-handle 'make-tray (bezel-tray-new icon-path tooltip))
               'object #t))

(define (set-tray-tooltip! tray tooltip)
  (require-alive! 'set-tray-tooltip! tray)
  (ok! 'set-tray-tooltip! (bezel-tray-set-tooltip (ptr-of tray) tooltip)))

(define (tray-show! tray)
  (require-alive! 'tray-show! tray)
  (ok! 'tray-show! (bezel-tray-set-visible (ptr-of tray) 1)))

(define (tray-hide! tray)
  (require-alive! 'tray-hide! tray)
  (ok! 'tray-hide! (bezel-tray-set-visible (ptr-of tray) 0)))

;; Desktop notification through the tray. Icons: 'information (default),
;; 'warning, 'critical. timeout-ms 0 lets the platform decide.
(define (tray-notify! tray title text
                      #:icon [icon 'information]
                      #:timeout-ms [timeout-ms 10000])
  (define icon-code
    (case icon
      [(information) 0]
      [(warning) 1]
      [(critical) 2]
      [else (raise-argument-error 'tray-notify!
                                   "(or/c 'information 'warning 'critical)" icon)]))
  (require-alive! 'tray-notify! tray)
  (ok! 'tray-notify!
       (bezel-tray-show-message (ptr-of tray) title text icon-code timeout-ms)))

;; Attach a context menu (from menu!/menu-action!). The tray does not
;; take ownership — Bezel menus live until application teardown.
(define (tray-set-menu! tray menu)
  (require-alive! 'tray-set-menu! tray)
  (require-alive! 'tray-set-menu! menu)
  (ok! 'tray-set-menu! (bezel-tray-set-menu (ptr-of tray) (ptr-of menu))))
