#lang scribble/doc
@(require scribble/manual
          (for-label bezel
                     racket/base))

@title{Bezel: Qt 6 bindings for Racket}
@author{@(author+email "turinglambdaai" "turinglambdaai@users.noreply.github.com")}

Bezel binds @hyperlink["https://www.qt.io/"]{Qt 6} (Widgets) to Racket:
real native widgets, styled with Qt Style Sheets, on macOS, Windows and
Linux.

@table-of-contents{}

@section{Quick start}

@racketblock[
(require bezel)

(define n (box 0))
(define count (make-label "Clicked 0 times"))
(define btn (make-button "Click me"))
(connect! btn "clicked()" (lambda _
  (set-box! n (add1 (unbox n)))
  (widget-set-text! count (format "Clicked ~a times" (unbox n)))))

(define win (make-window #:title "Hello Bezel" #:size '(320 140)))
(layout! win (vbox count btn))
(run win)
]

Bezel ships as a Racket package plus a small C++ shim (@tt{libbezel})
compiled against Qt 6. Install the shim from the releases page or build
it:

@commandline{cmake -S bezel-shim -B bezel-shim/build -DCMAKE_BUILD_TYPE=Release}
@commandline{cmake --build bezel-shim/build}

@section{Threading model}

Any Racket thread may call any Bezel function; calls from non-GUI
threads are marshaled onto the Qt GUI thread by a cooperative queue
(see @hyperlink["https://github.com/turinglambdaai/bezel/blob/main/docs/architecture.md"]{docs/architecture.md}).
Signal handlers run on Bezel's dispatcher thread — plain Racket code
works there, and widget calls marshal back automatically.

@section{API}

@defmodule[bezel]

The full API surface is indexed in the repository README and
@hyperlink["https://github.com/turinglambdaai/bezel"]{repository docs};
names follow @tt{make-widget} / @tt{widget-set-text!} conventions:

@itemlist[
 @item{Lifecycle: @racket[make-application], @racket[run], @racket[quit!],
       @racket[process-events!], @racket[bezel-cleanup!]}
 @item{Widgets: @racket[make-window], @racket[make-label], @racket[make-button],
       @racket[make-line-edit], @racket[make-combo], @racket[make-slider],
       @racket[make-table-widget], ... — every constructor also accepts
       @racket[#:parent]}
 @item{Generator-backed classes: @racket[radio-new], @racket[groupbox-new],
       @racket[doublespin-new], @racket[lcd-new], @racket[tabs-new],
       @racket[stacked-new], @racket[splitter-new], @racket[richtext-new]}
 @item{Layouts: @racket[layout!], @racket[vbox], @racket[hbox], @racket[grid],
       @racket[form], @racket[stretch]}
 @item{Signals: @racket[connect!], @racket[disconnect!],
       @racket[emit-test-signal!]}
 @item{Timers: @racket[after!], @racket[every!], @racket[stop-timer!]}
 @item{Dialogs: @racket[msg-question], @racket[get-open-file-name],
       @racket[get-save-file-name]}
 @item{Desktop integration: @racket[clipboard-set-text!],
       @racket[make-tray], @racket[window-status-bar],
       @racket[window-toolbar]}
 @item{Error reporting: @racket[install-sentry-reporter!]}
 @item{Update checks: @racket[check-for-update],
       @racket[check-and-prompt-update!] — best-effort version-feed
       comparison with a native prompt}
 @item{Object model: @racket[bezel-alive?], @racket[bezel-delete!],
       @racket[qt-object-name]}
 @item{Verification: @racket[widget-grab-png] — real PNG bytes of any widget}]

@section{Packaging applications}

@commandline{raco bezel package --entry my-app.rkt --name MyApp --dest dist}

produces a self-contained application folder (embedded executable plus
bundled native runtime). Signing helpers for Windows and macOS and the
full walkthrough live in @tt{docs/APP_PACKAGING.md}.
