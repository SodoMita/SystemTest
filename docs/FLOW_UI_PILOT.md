# Flow UI Pilot — minetest-flow in System Looting

**Branch:** arena/01a0642b-systemtest
**Date:** 2026-09-02
**Owner claim:** WP5 — HUD & UI (`mods/apis/sl_gui/**`)

Experiment: vendor [minetest-flow](https://github.com/luk3yx/minetest-flow)
(a declarative, auto-layout formspec library) and rebuild one real UI with it,
to answer "does it make making UI easier or better?" honestly.

**Verdict up front:** yes for self-contained popups — the DM terminal rewrite
deleted ~70 lines of string assembly + manual input parsing and replaced it
with a ~90-line widget tree whose state, redraws, and input decoding are
handled by the library — and it is *more* robust (sanitised input, no
out-of-frame layout drift, roster changes re-validated on every action). Flow
is **not** a fit for the big unified-inventory frame (hand-rolled `model[]`
preview, tab-strip `image_button`s, `container[]` embedding, a fixed
`size[12,…]` with pixel-perfect widget budget) — that code stayed as is.

## What was added

- `mods/external/flow/` — vendored flow @ `e886742` (2026-03-02), LGPL-2.1.
  Runtime files only; upstream commit recorded in `VENDORED.md`.
- `mods/external/formspec_ast/` — vendored formspec_ast @ `2ac09aa`
  (2024-08-08), MIT, flow's hard dependency (renders widget trees to
  formspec strings and parses them back). `VENDORED.md` records provenance.
- `mods/apis/sl_gui/mod.conf` — `flow` added to `depends`.
- `tests/flow_gui_test.lua` — new headless suite (40 checks) that loads the
  real vendored libraries + sl_gui under `tests/minetest_stub.lua` and drives
  the flow terminal end-to-end. Gated in `.github/workflows/soak.yml`.

## What was converted — the Secure Link DM terminal

`mods/apis/sl_gui/dm_system.lua`, shown by `/sl_dm_ui` / `/sl_comms` and by
the inventory Comms tab's "OPEN FULL TERMINAL" button (that button calls the
chat command, so it picked the new UI up with zero changes).

### Before (string formspec, ~60 lines of UI code + 45-line field handler)

- `get_dm_formspec()` concatenated ~11 hand-placed strings
  (`size[8,7]`, every widget with literal `x,y;w,h` coordinates).
- A `register_on_player_receive_fields` block decoded raw textlist events
  (`explode_textlist_event` + `type == "CHG"` + index bookkeeping) and kept a
  module table `dm_ui_selection[sender]` for "which target is selected".
- Every action re-showed the form manually:
  `minetest.show_formspec(sender, "sl_gui:dm", get_dm_formspec(sender))` —
  three separate call sites for success/error/no-target, and re-showing meant
  re-deciding the selected target from the module table each time.
- Errors went to chat; the form itself could not show them without more
  hand-rolled state.

### After (flow widget tree, ~90 lines of UI code + one shared callback)

```lua
dm_flow_gui = flow.make_gui(function(player, ctx)
    -- rows: Labels, gui.Textlist{name="dm_target", listelems=targets},
    -- gui.Field{name="dm_message", on_key_enter=try_send},
    -- gui.HBox{gui.Spacer{}, Button TRANSMIT, Button CLOSE}
end)
-- opening:  dm_flow_gui:show(player)
-- closing:  dm_flow_gui:close(player)
-- redraw:   a callback returning true
```

What the library now does for us:

| Concern | Old code | Flow code |
|---|---|---|
| Layout | hand-placed `x,y;w,h` for every widget; `size[8,7]` fixed | widget tree (VBox/HBox/Label/Field/Textlist/Button); window auto-sizes to content |
| Selected target | raw `CHG` events + `dm_ui_selection` table + re-seed on every re-show | `ctx.form.dm_target` — flow decodes the event, range-checks it, and remembers it across redraws |
| Typed message | re-read from `fields` on each click, lost on re-show | `ctx.form.dm_message` survives redraws; cleared by setting it to `""` |
| Re-showing after send | 3 manual `show_formspec` sites | `return true` from the callback; flow re-renders |
| Enter-to-send | impossible (field close-on-enter disabled, no handler) | `on_key_enter` on the Field |
| Input validation | none (a fake client could send anything) | flow drops values that were never shown / are out of range / contain control chars |
| Ghost roster change mid-form | stale list until next open | roster re-read on every build; stale selection re-validated or dropped, empty roster switches the form to a "NO TARGETS AVAILABLE" state |
| Errors in-form | chat only | `ctx.form.dm_error` renders a red line on the next redraw |

The DM *logic* (`send_dm`, cooldown, ghost seal, chat styling, commands) was
untouched — only the UI front end changed. When `flow` is not loaded (headless
stubs that dofile `sl_gui` directly), `dm_system.lua` degrades to the classic
string terminal, so no existing test or tooling broke.

## Test coverage added

`tests/flow_gui_test.lua` (run: `luajit tests/flow_gui_test.lua`, gated in
soak.yml) loads the vendored `formspec_ast` + `flow` under the engine stub,
loads `sl_modebase` + `sl_gui`, then proves the whole pipeline:

- libs and mods load; `game_mode.dm_flow_gui` is the flow terminal
- `/sl_dm_ui` opens a `flow:…` form; it renders title, roster, field, buttons;
  sender excluded; roster members present; output parses back with
  `formspec_ast` and carries a sane `size[]`
- `CHG:2:` textlist event → flow decodes → redraw with same form name
- TRANSMIT delivers exactly one DM to the *selected* target, sender gets the
  confirmation, message box comes back empty (cleared + redrawn)
- re-selection to row 1 + Enter key delivers to the new target
- ghosts dropping off the roster turns the next send into an in-form error
  ("No target selected") and a no-targets layout, with no chat leakage
- CLOSE LINK closes the flow form; later events are ignored
- terminal refuses to open when every target is sealed
- `game_mode.get_dm_formspec(player)` still returns a parseable standalone
  formspec (string API preserved for embedding/tests)

## Stub gaps the pilot had to fill (all engine-parity, in the new test)

The shared `tests/minetest_stub.lua` predates flow and was missing a few
engine APIs flow/formspec_ast rely on; the new test fills them with real
engine semantics rather than touching the shared stub:

- `minetest.get_modpath(name)` per-mod path map (flow + formspec_ast are real
  mods now)
- `minetest.close_formspec`, `minetest.is_singleplayer`,
  `minetest.get_player_information` (formspec version + lang, like a real
  client), `minetest.is_yes`
- a *working* `explode_textlist_event` (the stub's canned
  `{type="nothing"}` would break flow's textlist decoding)
- `string.trim` (Luanti string-library extension)
- auto-noop `set_*` methods on player objects (running_system calls
  `player:set_fov` from a globalstep)

## Observations for future conversions

**Where flow shines:** standalone forms and dialogs (this terminal, the
`summon_ghost` dialog, `character_outfit` if it ever stops needing the model
element). Stateful popups with a list + text input are exactly its sweet spot:
the ctx-as-state pattern removed an entire class of "forgot to re-seed the
selection" bugs.

**Where it does not fit (yet):**
- The unified inventory frame is a fixed `size[12,…]` canvas with a 3D
  `model[]` preview, transparent overlay click-target, six custom-painted tab
  buttons, and per-tab content that must slot into exact bands below a header.
  Flow has no `model` wrapper, no `real_coordinates` pixel budget, and its
  whole point is letting go of exact placement. The existing string tabs stay.
  (Embedding flow content *inside* a hand-built frame is possible via
  `render_to_formspec_string(player, ctx, false)` — it returns the content +
  its size — but the DM terminal does not need it.)
- Multi-element styling knobs (font_size etc.) are partial; the game's global
  formspec prepend (sl_formspec) styles buttons/labels anyway, and flow
  content inherits that prepend like any other formspec.
- Flow renders `formspec_version[7]`-family output and asks the client which
  formspec version it speaks (`get_player_information`); fine on the modern
  Luanti this game targets, not something to backport to the 5.0-era
  `formspec_version[4]` string code.

**Process notes:** vendored code is pure Lua and loads under the headless
stub, so flow UIs are fully testable without an engine — that is what made
this pilot cheap. Keep upstream files byte-identical (only runtime files were
copied) so future updates are a re-copy + re-run of `tests/flow_gui_test.lua`.

## Regression status

- `luajit -bl` syntax gate over all mods (incl. vendored libs): clean
- `tests/flow_gui_test.lua`: 40/40
- `tests/smoke_test.lua`: 235/235
- `tests/ui_layout_test.lua`: identical to master baseline (115/1 — the known,
  pre-existing `monster_spawner` widget-overlap failure that is documented in
  the HEAD merge message and keeps that suite ungated)
