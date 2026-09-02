# formspec_ast (vendored)

[formspec_ast](https://github.com/luk3yx/formspec_ast) — "a mod library to help
other mods interpret formspecs" by luk3yx (MIT, see LICENSE.md).

Hard dependency of the vendored `flow` mod (../flow): flow renders widget trees
into formspec_ast trees and uses `formspec_ast.unparse` to emit the final
formspec string. Also usable standalone (parsing/sanitising formspecs).

- Upstream: https://github.com/luk3yx/formspec_ast
- Vendored commit: `2ac09aa32d8ccac6936eef3cd93878b672cc220d` (2024-08-08)
- No dependencies of its own.

Only the runtime files were copied: init.lua, core.lua, elements.lua,
helpers.lua, safety.lua, mod.conf, LICENSE.md. Upstream's doc/tests and the
generator scripts were dropped. To update, re-copy from a newer upstream
commit and re-run `tests/flow_gui_test.lua`.
