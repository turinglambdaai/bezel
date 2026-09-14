#lang racket/base

;; Standard modal dialogs. These block in the Qt event loop; call them
;; from handlers (or the main thread before run). Return #t for
;; Yes/Ok, #f for No/Cancel.
;;
;;   (msg-question "Delete 3 items?" #:parent win)

(provide msg-information msg-warning msg-question)

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
