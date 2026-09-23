#lang racket/base

;; Standard modal dialogs. These block in the Qt event loop; call them
;; from handlers (or the main thread before run). Return #t for
;; Yes/Ok, #f for No/Cancel.
;;
;;   (msg-question "Delete 3 items?" #:parent win)

(provide msg-information msg-warning msg-question
         get-open-file-name
         get-save-file-name)

(require "private/errors.rkt"
         "private/objects.rkt"
         "private/raw.rkt")

(define (dialog-answer who r)
  (cond [(= r 1) #t]
        [(= r 0) #f]
        [else (raise-bezel-error who)]))

(define (msg-information text #:parent [parent #f] #:title [title ""])
  (when parent (require-alive! 'msg-information parent))
  (dialog-answer
   'msg-information
   (bezel-msg-information (and parent (ptr-of parent)) title text)))

(define (msg-warning text #:parent [parent #f] #:title [title ""])
  (when parent (require-alive! 'msg-warning parent))
  (dialog-answer
   'msg-warning
   (bezel-msg-warning (and parent (ptr-of parent)) title text)))

(define (msg-question text #:parent [parent #f] #:title [title ""])
  (when parent (require-alive! 'msg-question parent))
  (dialog-answer
   'msg-question
   (bezel-msg-question (and parent (ptr-of parent)) title text)))

;; ---- native file dialogs ---------------------------------------------------
;;
;; Same modal contract as msg-*: call from a handler or the main thread.
;; Return the chosen path as a string, or #f when the user cancels.
;;
;;   (get-open-file-name #:parent win
;;                       #:caption "Open plot"
;;                       #:filter "Images (*.png *.jpg);;All (*)")

(define (file-dialog who ffi parent caption dir filter)
  (when parent (require-alive! who parent))
  (define p (ok-string who
                       (ffi (and parent (ptr-of parent)) caption dir filter)))
  (begin0 (let ([path (cstring->string/utf8 p)])
            (and (not (string=? path "")) path))
    (bezel-free p)))

(define (get-open-file-name #:parent [parent #f]
                            #:caption [caption ""]
                            #:directory [dir ""]
                            #:filter [filter ""])
  (file-dialog 'get-open-file-name bezel-get-open-file-name parent caption dir filter))

(define (get-save-file-name #:parent [parent #f]
                            #:caption [caption ""]
                            #:directory [dir ""]
                            #:filter [filter ""])
  (file-dialog 'get-save-file-name bezel-get-save-file-name parent caption dir filter))
