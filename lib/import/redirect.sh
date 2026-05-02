#!/usr/bin/env bash
# Deprecation redirect for the retired `clift import` command.
#
# `clift import` was built on the wrong premise (adopt-into-existing-CLI).
# Its replacement is `clift init <name> --from PATH`, which generates a
# fresh CLI and folds the source Taskfile's tasks in during init.
#
# Kept for one release as a soft landing — prints a single redirect line
# and exits 2 (usage error). Once the deprecation window closes the entire
# `lib/import/` directory can be removed.

set -euo pipefail

echo "error: \`clift import\` is gone. Use \`clift init <name> --from PATH\` instead." >&2
exit 2
