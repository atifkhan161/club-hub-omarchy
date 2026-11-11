# AGENTS.md — sports-omarchy-plugin

An Omarchy shell plugin ("sports"): QML/Quickshell code that runs inside the long-lived
`omarchy-shell` process (bar widget / panel). Not a desktop app, not a script — see the
omarchy skill before writing anything.

## First step: load the omarchy skill

- Load via the `skill` tool (`id: omarchy`), or read it on disk at
  `~/.claude/skills/omarchy/` (also symlinked as `~/.agents/skills/omarchy/`).
- Before writing any QML, read `~/.claude/skills/omarchy/plugins.md` — it covers plugin
  UI safety (`Text.PlainText` for untrusted data), motion (`Style.duration(ms)`), i18n
  (flat JSON catalogs in `i18n/`, `Commons.Translations`), and bar sections. Don't
  re-derive those rules here.
- Never edit anything under `/usr/share/omarchy/` — package-owned, overwritten on
  update. Reading it is safe and encouraged.

## Initialising the repo (it is empty until you do this)

```bash
git init                       # default branch is master (global git config)
```

Then scaffold the plugin. Minimal layout that the shell accepts:

```
manifest.json          required; see contract below
BarWidget.qml          if kinds includes "bar-widget"
Panel.qml              if kinds includes "panel"
tests/                 python3 tests + offscreen QML harness
```

## Manifest contract (enforced by `omarchy plugin validate .` — run it after every manifest edit)

- `schemaVersion` must be the JSON **number** `1` (the string `"1"` is rejected).
- Required fields: `id`, `name`, `version`, `kinds`, `entryPoints`.
- `id`: `^[A-Za-z0-9][A-Za-z0-9._-]*$`, no `omarchy.` prefix (reserved for first-party).
  Pick e.g. `atif.sports`; Omarchy names the installed directory after the id.
- Every kind promises an entry point: `bar→bar`, `bar-widget→barWidget`, `menu→menu`,
  `overlay→overlay`, `panel→panel`, `service→service`. A kind without its key installs
  but silently does nothing.
- Entry points: relative paths, no `..`, file must exist. No symlinks anywhere inside the
  plugin folder — note this also fails validation when the *folder itself* is a symlink;
  validate against the real path.
- `barWidget.defaultSection` (optional): one of `left`, `centerBegin`, `center`,
  `centerEnd`, `tray`, `right`. For a widget that belongs next to the clock, use
  `centerBegin`/`centerEnd`, not `center` (that would push the clock off center).

## Dev / test / install loop

- The shell only discovers plugins in `~/.config/omarchy/plugins/<id>/`. During
  development, copy or symlink the checkout there, or install the git repo with
  `omarchy plugin add <url-or-local-path> --enable`.
- `omarchy plugin validate <folder>` — the same manifest checks the shell runs at load
  time; run before anything else.
- Saving any file under `~/.config/omarchy/plugins/` hot-reloads the plugin. If an edit
  doesn't apply: `omarchy-shell shell rescanPlugins`. Full restart: `omarchy restart shell`.
- Enable with placement: `omarchy plugin enable <id> --section right`. Disable:
  `omarchy plugin disable <id>`.
- Only one installed copy per id; if the id is taken, `omarchy plugin add` refuses.
  Check what's installed: `omarchy plugin list`.

## Tests and verification (no CI yet — run locally)

- Python helpers/tests: `python3 -m unittest discover -s tests` (pattern used by
  `~/.config/omarchy/plugins/tinyworkshop.livewall`).
- Offscreen QML logic tests (pattern from `~/.config/omarchy/plugins/superwhisper-panel`):
  run `quickshell` with `QT_QPA_PLATFORM=offscreen`, unset `QT_QPA_PLATFORMTHEME`, unset
  `WAYLAND_DISPLAY`/`DISPLAY`, and set `OMARCHY_SHELL=/usr/share/omarchy/shell` for the
  `qs.Commons`/`qs.Ui` modules. A missing runtime must fail the test, not skip it.
- `qmllint` is installed; use it on changed QML files.

## Reference plugins to read (never edit)

- First-party: `/usr/share/omarchy/shell/plugins/` — `panels/clock` (simple bar widget),
  `reminders` (overlay). IDs, kinds, entry points are cataloged in its `README.md`.
- Third-party: `~/.config/omarchy/plugins/tinyworkshop.livewall` (panel + bar-widget,
  i18n, tests) and `~/.config/omarchy/plugins/superwhisper-panel` (offscreen QML test
  harness, fixture-daemon pattern).

## Shell command gotchas

- Use `omarchy <group> <action>` form; `omarchy commands` lists everything,
  `omarchy <group> --help` for one group.
- Always `omarchy debug --no-sudo --print` — the bare command can hang on an
  interactive sudo prompt.
- Plugin network access must be explicit: fixed HTTPS sources, timeouts, size limits,
  validation. Treat all text (network, files, IPC) as untrusted markup input.
