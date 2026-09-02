# flow (vendored)

[luanti-flow](https://github.com/luk3yx/minetest-flow) — "an experimental layout
manager and formspec API replacement" by luk3yx (LGPL-2.1+, see LICENSE.md).

Vendored for the UI pilot that converted the sl_gui DM terminal from raw
formspec strings to a declarative widget tree. Kept under the upstream mod name
(`flow`) so upstream code works unmodified; the mod is only an `optional_depends`
of `sl_gui` and does nothing unless something builds a GUI with it.

- Upstream: https://github.com/luk3yx/minetest-flow
- Vendored commit: `e886742134d12b96f478e3068fc00bacd5bbd16b` (2026-03-02)
- Depends on: `formspec_ast` (vendored alongside, see ../formspec_ast)
- Optional deps kept from upstream (fs51, hud_fs) so loading behaviour matches
  upstream; neither ships with this game.

Only the runtime files were copied: init.lua, layout.lua, expand.lua,
input.lua, widgets.lua, popover.lua, embed.lua, locale/, mod.conf, LICENSE.md.
Upstream's doc/ and test.lua were dropped. To update, re-copy the same files
from a newer upstream commit and re-run `tests/flow_gui_test.lua`.
