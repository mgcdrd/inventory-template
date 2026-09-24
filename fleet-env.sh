#!/usr/bin/env bash
# Load every instance directory for a fleet-wide run (harden, vm-migrate,
# proxmox-vm-manage — deployments that target `hosts: all` and are not tied
# to one instance).
#
# SOURCE it from the deployment directory, don't execute it:
#
#   source ../../inventory-common/fleet-env.sh          # every instance
#   source ../../inventory-common/fleet-env.sh dev      # only `dev` and dev_*
#   ansible-playbook site.yml --limit <hosts>
#
# It takes the deployment's own `inventory =` list from ansible.cfg and
# appends each instances/<service>/<name>/ directory, then exports the result
# as ANSIBLE_INVENTORY (which overrides ansible.cfg's value for this shell).
# Instances are matched by name, so name them <env>_<set> (dev_a, prd_b) for
# the env filter to work.
#
# Fleet runs load many instances at once. Vars defined on an instance-named
# group (webproxy_dev_a) stay with that instance's hosts, but a var on a
# shared group (k8smasters, webproxy) is overwritten by whichever instance
# loads last. Fleet deployments should only rely on root-tier vars and
# per-host facts. Per-instance deployments (k8s, k8s-platform) select one
# instance with DEPLOY_INSTANCE instead and don't use this.
#
# Under AWX this isn't used: add each instance as an inventory source, and set
# fleet_check=false on the job template so harden's fleet check is skipped.

_fleet_root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_fleet_env="${1:-}"

# The deployment's own inventory list, resolved by ansible-config. Unset
# ANSIBLE_INVENTORY first so sourcing this twice doesn't stack on itself.
_fleet_base="$(env -u ANSIBLE_INVENTORY ansible-config dump --only-changed 2>/dev/null </dev/null \
  | sed -n 's/^DEFAULT_HOST_LIST([^)]*) = //p')"
if [[ -z "$_fleet_base" ]]; then
  echo "fleet-env: no 'inventory =' found for $PWD — run this from a deployment directory with an ansible.cfg" >&2
  unset _fleet_root _fleet_env _fleet_base
  return 1
fi

_fleet_paths="$(_FLEET_BASE="$_fleet_base" _FLEET_ROOT="$_fleet_root" _FLEET_ENV="$_fleet_env" python3 - <<'PY'
import ast, glob, os, sys

root = os.environ["_FLEET_ROOT"]
env = os.environ["_FLEET_ENV"]
base = ast.literal_eval(os.environ["_FLEET_BASE"])

# Drop base entries that don't exist (e.g. an unexpanded ${DEPLOY_INSTANCE}).
paths = [os.path.realpath(p) for p in base if os.path.exists(p)]

patterns = [f"{env}", f"{env}_*"] if env else ["*"]
found = []
for pat in patterns:
    for d in sorted(glob.glob(os.path.join(root, "instances", "*", pat))):
        if os.path.isfile(os.path.join(d, "hosts.yml")):
            found.append(os.path.realpath(d))

if not found:
    print("fleet-env: no instances match" + (f" '{env}'" if env else ""), file=sys.stderr)
    sys.exit(1)

for d in found:
    if d not in paths:
        paths.append(d)

print(",".join(paths))
print("\n".join(os.path.relpath(d, root) for d in found), file=sys.stderr)
PY
)" || { unset _fleet_root _fleet_env _fleet_base _fleet_paths; return 1; }

export ANSIBLE_INVENTORY="$_fleet_paths"
# Marker read by fleet-aware playbooks (harden's first play) to confirm this
# script ran. Holds the env filter, or "all".
export FLEET_ENV_LOADED="${_fleet_env:-all}"
echo "fleet-env: ANSIBLE_INVENTORY set (${_fleet_env:-all environments})" >&2

unset _fleet_root _fleet_env _fleet_base _fleet_paths
