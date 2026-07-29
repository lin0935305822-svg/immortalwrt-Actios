#!/bin/sh
# The production TLS listener exposes only the authenticated local-control
# protocol and its public identity record.  Keep this legacy recovery helper
# non-observable when uhttpd is enabled in production.
printf 'Status: 404 Not Found\r\nContent-Type: text/plain; charset=utf-8\r\nCache-Control: no-store\r\n\r\nNot found\n'
