#!/usr/bin/env bash
# Source this (don't execute) before running ansible-inventory/ansible-playbook
# against a deployment that consumes build.foreman.yml:
#   source ../../inventory-<client>/foreman-inventory-env.sh
#
# theforeman.foreman.foreman doesn't template its own config file, so these
# have to be real environment variables — see build.foreman.yml. Nothing is
# written to disk; the credential only lives in this shell's environment.
#
# Requires a dedicated, read-only Foreman user scoped to Hosts (Viewer role
# or narrower) — do not point this at the customer's Foreman admin account.
# Fill in the real hostname/Vault path below for this engagement.
set -euo pipefail

export FOREMAN_URL="https://foreman.example.com"
export FOREMAN_USER="svc-ansible-inventory"
export FOREMAN_PASSWORD="$(vault kv get -mount=infra -field=inventory_password <env>/foreman)"
