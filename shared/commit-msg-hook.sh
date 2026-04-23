#!/usr/bin/env bash
# commit-msg hook: validate commit message format with commitlint (angular preset).
#
# Installed into .git/hooks/commit-msg by setup.sh.
# Requires @commitlint/cli and @commitlint/config-angular in package.json devDependencies.
# Run `npm install` after setup.sh to activate.
set -e
exec npx --no-install commitlint --edit "$1"