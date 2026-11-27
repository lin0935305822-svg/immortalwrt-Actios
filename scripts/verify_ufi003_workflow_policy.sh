#!/bin/sh
# Fail before an expensive cloud build when workflow safety invariants regress.
set -eu

root="${1:-.}"
cd "$root"

workflow='.github/workflows/Build_高通410 imm.yml'
[ -f "$workflow" ] || { echo "missing 410 workflow: $workflow" >&2; exit 1; }

require_text() {
    grep -Fq -- "$1" "$workflow" || {
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

if [ -e '.github/workflows/Build_??410 imm.yml' ]; then
    echo 'Remove the malformed duplicate 410 workflow; it bypasses the reviewed fix' >&2
    exit 1
fi

require_text 'Apply UFI003 WCN36xx scan band fix'
require_text 'Verify compiled UFI003 WCN36xx source'
require_text 'scripts/apply_ufi003_wcn36xx_fix.sh'
require_text '--prepared-source'
require_text 'TZ: Asia/Shanghai'
require_text '/bin/sh ./scripts/run_ufi003_preflight.sh .'
require_text '--control-root "$GITHUB_WORKSPACE"'
require_text '--rootfs-root "$GITHUB_WORKSPACE/openwrt"'
require_text 'Build time zone: $TZ'
require_text 'svci-release-provenance.v1'
require_text 'sourceCommit'
require_text 'workflowRunUrl'
require_text 'FLASH_PACKAGE_SHA256'

for script in \
    './scripts/verify_ufi003_workflow_policy.sh .' \
    './scripts/test_wcn36xx_scan_band_guard.sh .' \
    './scripts/verify_ufi003_config_consistency.sh config/ufi003.config' \
    './scripts/test_rfcomm_a30m_bluez_readiness.sh .' \
    './scripts/test_ufi003_dropbear_startup.sh .' \
    './scripts/test_obdclaw_local_control.sh .' \
    './scripts/test_obdclaw_runner_auth.sh .' \
    './scripts/test_obdclaw_runner_authority_install.sh .' \
    './scripts/test_svci_ufi003_source_stage.sh .' \
    './scripts/verify_svci_ufi003_release.sh .'; do
    grep -Fq "$script" scripts/run_ufi003_preflight.sh || {
        echo "unified preflight is missing: $script" >&2
        exit 1
    }
done

echo 'SVCI UFI003 workflow policy gate passed.'
