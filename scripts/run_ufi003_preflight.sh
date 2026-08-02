#!/bin/sh
# Single source of truth for every UFI003 release or rootfs hot-patch preflight.
set -eu

root="${1:-.}"
cd "$root"

/bin/sh ./scripts/verify_ufi003_workflow_policy.sh .
/bin/sh ./scripts/verify_ufi003_config_consistency.sh config/ufi003.config
/bin/sh ./scripts/test_ufi003_sta_profile.sh .
/bin/sh ./scripts/test_ufi003_usb_rndis_management.sh .
/bin/sh ./scripts/test_obdclaw_local_control.sh .
/bin/sh ./scripts/test_obdclaw_runner_auth.sh .
/bin/sh ./scripts/test_obdclaw_runner_authority_install.sh .
/bin/sh ./scripts/test_svci_ufi003_source_stage.sh .
/bin/sh ./scripts/verify_svci_ufi003_release.sh .

echo 'SVCI UFI003 unified preflight passed.'
