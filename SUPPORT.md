# Support and project status

## Project status

Bezel is an actively developed MIT-licensed open-source project. The
README roadmap shows what is done; `CHANGELOG.md` shows what shipped
when. CI runs the full suite (build, headless real-object tests,
packaging, silent self-update end to end) on Linux, Windows, and macOS
for every change.

## What is covered — and what deliberately is not

Covered: Qt Widgets bindings, layouts, menus/toolbars/status bars,
dialogs, timers, data binding (observables), desktop integration
(clipboard/tray), error reporting hooks, update checks and silent
self-update, packaging (folders, `.app`, Inno Setup, dmg, AppImage) and
signing helpers.

Deliberately not covered (see README): the Qt model/view framework,
Qt Quick/QML, and WebEngine/WebView embedding. Bezel targets
professional-tools UI on Qt Widgets; if you need those, Bezel is not
(yet) the right tool.

## Getting help

- **Bugs and feature requests**: open a GitHub issue with the output of
  `raco bezel doctor` and a minimal reproducing module.
- **Questions and design discussion**: GitHub Discussions on this
  repository.
- **Commercial support**: not offered at this time; there is no SLA, no
  LTS cadence, and the bus factor is currently one — factor that into
  adoption decisions.

## Security

Report suspected vulnerabilities privately via GitHub security
advisories for this repository. Note that a prebuilt Bezel runtime
redistributes Qt libraries; Qt's own security advisories apply to those
binaries (see `docs/COMMERCIAL_RELEASE.md` for licensing obligations).
