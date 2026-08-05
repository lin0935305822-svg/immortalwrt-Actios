#!/bin/sh
# Public 410 local-diagnostics endpoint.  The legacy implementation name is
# retained only to preserve the already-reviewed authorization boundary.
exec /www/cgi-bin/obdclaw-runner.cgi "$@"
