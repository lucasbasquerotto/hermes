#!/bin/sh
# Fix volume permissions for vault user (uid 100)
chown -R vault:vault /vault/data
# Run vault as root (internal service behind CF tunnel)
exec vault "$@"
