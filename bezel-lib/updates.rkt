#lang racket/base

;; Best-effort application update checks.
;;
;;   (after! 1000 (lambda ()
;;     (check-and-prompt-update!
;;      #:feed "https://example.com/myapp-updates.json"
;;      #:current "1.2.3"
;;      #:parent win)))
;;
;; The feed is one static JSON file the application author hosts anywhere:
;;
;;   {"version": "1.3.0",
;;    "url": "https://github.com/me/myapp/releases/latest",
;;    "notes": "Optional release notes"}
;;
;; Check semantics (deliberately quiet — an update check must never take
;; the application down): unreachable feeds, timeouts, malformed JSON, and
;; missing fields all return #f rather than raising. Pre-release suffixes
;; in versions are ignored ("1.3.0-beta" compares as "1.3.0"), and a
;; leading v/V is tolerated.
;;
;; `check-and-prompt-update!` asks the user through the native modal
;; question dialog and opens the release page in the system browser on
;; confirmation. It does not download or replace anything — shipping the
;; update itself remains the distribution channel's job (see
;; docs/APP_PACKAGING.md).

(provide (struct-out update-info)
         newer-version?
         check-for-update
         check-and-prompt-update!
         download-update!
         apply-update!
         auto-update!
         packaged-app-root)

(require json
         ffi/unsafe
         file/sha1
         racket/format
         net/sendurl
         net/url
         racket/file
         racket/list
         racket/match
         racket/path
         racket/port
         racket/string
         "dialogs.rkt")

(struct update-info (version url notes) #:transparent)

;; Plainly-dotted versions: numeric elements only, padding with zeros so
;; "1.2" < "1.2.1". Non-numeric parts contribute 0, which makes
;; "1.3.0-beta" equal "1.3.0" — pre-release channels are out of scope.
(define (version->numbers v)
  (for/list ([part (in-list (string-split
                             (regexp-replace #px"^[vV]+" (string-trim v) "")
                             "."))])
    (define digits (regexp-match #px"^[0-9]+" part))
    (if digits (string->number (car digits)) 0)))

(define (newer-version? candidate current)
  (define a (version->numbers candidate))
  (define b (version->numbers current))
  (define n (max (length a) (length b)))
  (let loop ([a (append a (make-list (- n (length a)) 0))]
             [b (append b (make-list (- n (length b)) 0))])
    (cond [(> (car a) (car b)) #t]
          [(< (car a) (car b)) #f]
          [(null? (cdr a)) #f]     ; equal lists are not "newer"
          [else (loop (cdr a) (cdr b))])))

;; Parse the feed document; #f when it is not the expected shape.
(define (parse-feed j)
  (and (hash? j)
       (let ([v (hash-ref j 'version #f)]
             [u (hash-ref j 'url #f)])
         (and (string? v) (non-empty-string? v)
              (string? u) (non-empty-string? u)
              (update-info v u
                           (let ([n (hash-ref j 'notes #f)])
                             (if (string? n) n "")))))))

;; Fetch + parse inside a dedicated custodian so a timeout can close the
;; connection cleanly instead of leaking it to GC.
(define (fetch-update-info feed-url timeout-ms)
  (define result-ch (make-channel))
  (define cust (make-custodian))
  (parameterize ([current-custodian cust])
    (thread
     (lambda ()
       (channel-put
        result-ch
        (with-handlers ([exn:fail? (lambda (e) #f)])
          (parse-feed (call/input-url (string->url feed-url)
                                      get-pure-port
                                      read-json)))))))
  (begin0 (sync/timeout (/ timeout-ms 1000.0) result-ch)
    (custodian-shutdown-all cust)))

;; Blocking, best-effort: returns update-info only when the feed reports
;; a version newer than `current`; #f for "no update" and for every
;; failure mode (see module note). Call from a timer or background
;; thread so the request never stalls startup.
(define (check-for-update #:feed feed-url
                          #:current current-version
                          #:timeout-ms [timeout-ms 5000])
  (define info (fetch-update-info feed-url timeout-ms))
  (and info
       (newer-version? (update-info-version info) current-version)
       info))

;; Check, ask, and (on confirmation) open the release page in the system
;; browser. Returns the update-info when a newer version exists, #f
;; otherwise; note the modal dialog runs on the GUI thread like every
;; msg-* call — invoke this from the main thread, a handler, or a timer.
(define (check-and-prompt-update! #:feed feed-url
                                  #:current current-version
                                  #:parent [parent #f]
                                  #:timeout-ms [timeout-ms 5000])
  (define info (check-for-update #:feed feed-url
                                 #:current current-version
                                 #:timeout-ms timeout-ms))
  (and info
       (let ([open? (msg-question
                     (string-append
                      (format "Version ~a is available."
                              (update-info-version info))
                      (let ([n (update-info-notes info)])
                        (if (non-empty-string? n)
                            (string-append "\n\n" n)
                            "")))
                     #:parent parent
                     #:title "Update available")])
         (when open? (send-url (update-info-url info)))
         info)))

;; ---- silent self-update ---------------------------------------------------
;;
;; The full loop: check a feed, download the new application archive
;; (the zip of the folder `raco bezel package` produced), verify an
;; optional SHA-256, then hand off to a tiny out-of-process swapper.
;;
;; Replacing a running application in place is platform-hostile (Windows
;; locks the running exe, macOS keeps the bundle mapped), so the swap
;; happens from outside the process: apply-update! writes a small
;; script that waits for this process to exit, swaps the directory, and
;; relaunches. The caller exits right after apply-update! returns.

;; The app folder produced by raco bezel package, derived from the
;; running executable's location (exe at root on Windows, under bin/ on
;; Linux, under <name>.app/Contents/MacOS/bin/ on macOS).
(define (packaged-app-root)
  (define exe (find-executable-path (find-system-path 'exec-file)))
  (unless exe (error 'packaged-app-root "cannot locate the running executable"))
  (define dir (path-only exe))
  (define root
    (case (system-type)
      [(windows) (simplify-path dir #f)]
      [(macosx) (simplify-path (build-path dir 'up 'up 'up 'up) #f)]
      [else (simplify-path (build-path dir 'up) #f)]))
  ;; path-only/simplify-path keep a trailing slash; `mv` fails when the
  ;; destination carries one and does not exist, so strip separators.
  (string->path
   (string-trim (path->string root) "/" #:left? #f)))

;; Best-effort download of the update archive (any URL the feed's `url`
;; names; usually the same host as the feed). Returns the downloaded
;; file path or #f. `expected-sha1` (hex string) is optional.
(define (download-update! url [dest #f] #:sha1 [expected-sha1 #f])
  (with-handlers ([exn:fail? (lambda (e) #f)])
    (define out (or dest (make-temporary-file "bezel-update~a.zip")))
    (call-with-output-file out
      #:exists 'replace
      (lambda (o)
        (call/input-url (string->url url) get-pure-port
                        (lambda (i) (copy-port i o)))))
    (and (file-exists? out)
         (or (not expected-sha1)
             (string=? (string-downcase expected-sha1)
                       (sha1 (file->bytes out))))
         out)))

;; The C library owns the process id (Racket core exposes no portable
;; getpid; MSVC spells it _getpid).
(define getpid-ffi
  (get-ffi-obj (if (eq? (system-type) 'windows) '_getpid 'getpid)
               #f (_fun -> _int)
               (lambda () (lambda () 0))))

(define (app-name-from-root app-root)
  (path->string (last (explode-path (simplify-path app-root)))))

(define swapper-sh-template
  #<<SCRIPT
#!/bin/sh
# Bezel self-update swapper: wait -> extract -> swap -> relaunch.
APP_DIR="$1"; ARCHIVE="$2"; EXE_REL="$3"; APP_PID="$4"
LOG="$(dirname "$APP_DIR")/.bezel-swap.log"
exec >> "$LOG" 2>&1
echo "=== swap start $(date) pid=$$ app=$APP_DIR"
# kill -0 0 would always succeed (process group); 0 means "skip waiting"
if [ "$APP_PID" != "0" ]; then
  while kill -0 "$APP_PID" 2>/dev/null; do sleep 0.2; done
fi
PARENT="$(dirname "$APP_DIR")"
TMP="$PARENT/.bezel-update-tmp.$$"
mkdir -p "$TMP"
if command -v unzip >/dev/null 2>&1; then
  # </dev/null: an interactive unzip prompt would block forever here
  unzip -qo "$ARCHIVE" -d "$TMP" </dev/null
else
  python3 - "$ARCHIVE" "$TMP" <<'PY'
import sys, zipfile
zipfile.ZipFile(sys.argv[1]).extractall(sys.argv[2])
PY
fi
NEW="$(find "$TMP" -mindepth 1 -maxdepth 1 -type d | head -n 1)"
if [ -z "$NEW" ]; then rm -rf "$TMP"; exit 1; fi
mv "$APP_DIR" "$APP_DIR.old.$$"
mv "$NEW" "$APP_DIR"
rm -rf "$APP_DIR.old.$$" "$TMP"
"$APP_DIR/$EXE_REL" &
SCRIPT
)

;; Parameters arrive through the environment, not the command line:
;; one quote-escape bug in a nested Start-Process argument list hung
;; the whole update chain on real Windows.
(define swapper-ps1-template
  #<<SCRIPT
$AppDir = $env:BEZEL_SWAP_APPDIR
$Archive = $env:BEZEL_SWAP_ARCHIVE
$ExeRel = $env:BEZEL_SWAP_EXEREL
$AppPid = $env:BEZEL_SWAP_PID
$log = Join-Path (Split-Path -Parent $AppDir) ".bezel-swap.log"
function Log($m) { $m | Out-File -Append -Encoding utf8 $log }
Log "=== win swap start app=$AppDir"
if ($AppPid -and $AppPid -ne "0") {
  Wait-Process -Id $AppPid -ErrorAction SilentlyContinue
}
$parent = Split-Path -Parent $AppDir
$tmp = Join-Path $parent ".bezel-update-tmp"
if (Test-Path $tmp) { Remove-Item -Recurse -Force $tmp }
Expand-Archive -Path $Archive -DestinationPath $tmp -Force
$new = Get-ChildItem -Path $tmp -Directory | Select-Object -First 1
if (-not $new) { Log "no new dir in archive"; exit 1 }
$old = "$AppDir.old"
if (Test-Path $old) { Remove-Item -Recurse -Force $old }
Rename-Item $AppDir "$AppDir.old" -ErrorAction Stop
Move-Item $new.FullName $AppDir
Remove-Item -Recurse -Force $old, $tmp
Log "swap done"
Start-Process -FilePath (Join-Path $AppDir $ExeRel) -WorkingDirectory $parent
SCRIPT
)

;; Spawn the out-of-process swapper for `archive` (a zip of the new app
;; folder). Does not wait; the caller should (exit 0) immediately after.
;; Relaunches the new version on success.
(define (apply-update! archive)
  (unless (file-exists? archive)
    (raise-argument-error 'apply-update! "(and/c path? file-exists?)" archive))
  (define app-root (packaged-app-root))
  (define exe-rel
    (case (system-type)
      [(windows) (~a (app-name-from-root app-root) ".exe")]  ; exe sits at the app root
      [(macosx)
       (path->string (build-path (~a (app-name-from-root app-root) ".app")
                                 "Contents" "MacOS" "bin"
                                 (app-name-from-root app-root)))]
      [else (path->string (build-path "bin" (app-name-from-root app-root)))]))
  (define archive-path (path->string (path->complete-path archive)))
  (define pid (~a (getpid-ffi)))
  (case (system-type)
    [(windows)
     (define script (make-temporary-file "bezel-swap~a.ps1"))
     (display-to-file swapper-ps1-template script #:exists 'replace)
     ;; Parameters travel through the environment (inherited by
     ;; Start-Process) — no nested quoting anywhere. Start-Process
     ;; detaches the swapper so this process can exit immediately.
     (putenv "BEZEL_SWAP_APPDIR" (path->string app-root))
     (putenv "BEZEL_SWAP_ARCHIVE" archive-path)
     (putenv "BEZEL_SWAP_EXEREL" exe-rel)
     (putenv "BEZEL_SWAP_PID" pid)
     (apply subprocess #f #f #f (find-executable-path "powershell.exe")
            (list "-NoProfile" "-WindowStyle" "Hidden" "-ExecutionPolicy" "Bypass"
                  "-Command"
                  (format "Start-Process -WindowStyle Hidden powershell -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-File','~a'"
                          (string-replace (path->string script) "\\" "/"))))
     (void)]
    [else
     (define script (make-temporary-file "bezel-swap~a.sh"))
     (display-to-file swapper-sh-template script #:exists 'replace)
     ;; sh -c '... &' returns immediately; the swapper outlives us.
     (define cmd
       (format "nohup /bin/sh '~a' '~a' '~a' '~a' '~a' >/dev/null 2>&1 &"
               (path->string script) (path->string app-root) archive-path exe-rel pid))
     (apply subprocess #f #f #f "/bin/sh" (list "-c" cmd))
     (void)]))

;; Check -> download -> verify -> apply -> exit. Silent by design: returns
;; #f when no update exists or the download failed; never returns when the
;; update applies (the process exits and the swapper relaunches the new
;; version). Feed entries may add "sha1" over the archive named by "url".
(define (auto-update! #:feed feed-url
                      #:timeout-ms [timeout-ms 5000]
                      #:on-error [on-error void])
  (define info (check-for-update #:feed feed-url
                                 #:current (version-file-read)
                                 #:timeout-ms timeout-ms))
  (eprintf "UPDATE: check => ~a
" (and info (update-info-version info)))
  (cond
    [(not info) #f]
    [else
     (define downloaded
       (download-update! (update-info-url info)
                         #:sha1 (hash-ref (fetch-feed-json feed-url timeout-ms)
                                          'sha1 #f)))
     (eprintf "UPDATE: download => ~a
" (and downloaded 1))
     (cond
       [(not downloaded)
        (on-error "update download failed")
        #f]
       [else
        (eprintf "UPDATE: spawning swapper
")
        (apply-update! downloaded)
        (exit 0)])]))

;; ---- packaged version discovery -----------------------------------------------

;; The VERSION file raco bezel package writes into the app folder.
(define (version-file-read)
  (with-handlers ([exn:fail? (lambda (_) "0.0.0")])
    (string-trim
     (file->string (build-path (packaged-app-root) "VERSION")))))

(define (fetch-feed-json feed-url timeout-ms)
  (with-handlers ([exn:fail? (lambda (_) (hasheq))])
    (call/input-url (string->url feed-url) get-pure-port read-json)))
