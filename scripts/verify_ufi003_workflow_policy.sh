#!/bin/sh
# Fail before an expensive cloud build when workflow safety invariants regress.
set -eu

root="${1:-.}"
cd "$root"

workflow='.github/workflows/Build_高通410 imm.yml'
[ -f "$workflow" ] || { echo "missing 410 workflow: $workflow" >&2; exit 1; }

require_text() {
    grep -Fq "$1" "$workflow" || {
        echo "410 workflow policy missing: $1" >&2
        exit 1
    }
}

# TZ is a process environment setting.  System-wide mutation is optional,
# runner-dependent, and previously aborted an otherwise valid release build.
if grep -R -n -E '(^|[[:space:]])(sudo[[:space:]]+)?timedatectl[[:space:]]+set-timezone' .github/workflows; then
    echo 'workflow policy violation: do not mutate a runner system time zone; use TZ only' >&2
    exit 1
fi

require_text 'TZ: Asia/Shanghai'
require_text '/bin/sh ./scripts/run_ufi003_preflight.sh .'
require_text 'Build time zone: $TZ'

for script in \
    './scripts/verify_ufi003_workflow_policy.sh .' \
    './scripts/verify_ufi003_config_consistency.sh config/ufi003.config' \
    './scripts/test_obdclaw_local_control.sh .' \
    './scripts/test_obdclaw_runner_auth.sh .' \
    './scripts/verify_svci_ufi003_release.sh .'; do
    grep -Fq "$script" scripts/run_ufi003_preflight.sh || {
        echo "unified preflight is missing: $script" >&2
        exit 1
    }
done

echo 'SVCI UFI003 workflow policy gate passed.'
