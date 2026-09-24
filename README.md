inventory-template
===================

Skeleton for a new customer engagement's inventory repo. Clone or fork this,
push it to the customer's own SCM, and fill in the placeholders — don't
branch or fork `inventory-common` itself, since that has the lab's real
topology in it.

```
inventory-template/
├── hosts.yml            # mirrors inventory-common's real group structure, example.com placeholder hosts (k8s hosts excluded, see instances/)
├── instances/
│   └── k8s/example/     # one directory per k8s cluster: hosts.yml + group_vars/k8s_<name>/ — copy per additional cluster
├── fleet-env.sh         # source it from a deployment dir to load every instance for fleet runs (harden etc.)
├── build.foreman.yml    # dynamic inventory source — hosts on Foreman's "Build" subnet, populates the `building` group
├── foreman-inventory-env.sh  # sources FOREMAN_URL/USER/PASSWORD from Vault for build.foreman.yml — placeholder values, fill in per engagement
└── group_vars/
    ├── all.yml           # mirrors inventory-common's real keys, example.com placeholder values
    ├── building.yml      # SSH ProxyJump-through-Foreman wiring for NAT'd build-network hosts
    ├── keycloak.yml      # real keycloak/postgres hostnames + keepalived VIP
    ├── nut_server.yml    # firewall_zones for the UPS-attached host
    ├── ftp_lb.yml        # firewall_zones for the haproxy-lb group
    ├── vsftp.yml         # firewall_zones for the vsftp group
    ├── webproxy.yml      # firewall_zones for the webproxy group
    └── syslog.yml        # firewall_zones for the syslog group
└── host_vars/
    ├── foreman.example.com.yml  # rsyslog_file_inputs worked example (Foreman/Katello)
    ├── gitlab.example.com.yml   # rsyslog_file_inputs worked example (GitLab Omnibus)
    └── syslog.example.com.yml   # rsyslog_listeners/rsyslog_rulesets worked example (aggregator)
```

Every file has the *same shape* as the lab's real `inventory-common` —
same group names, same nesting, same host counts, same keys — so starting
an engagement is replacing values, not guessing what groups or files to
add. Add or remove groups/hosts/files freely once you're past the initial
placeholder swap; the shape is a starting point, not a requirement.

`host_vars/` only has worked examples for hosts where `inventory-common`
has real, nontrivial host-specific facts — not one file per host in
`hosts.yml`. Add more as the engagement's real hosts need host-specific
facts, and keep this in sync when `inventory-common` picks up a new
generalizable pattern (as opposed to one-off values only that lab needs).


Starting a new engagement
--------------------------

1. Clone or fork this repo, rename it `inventory-<client>`.
2. Point its remote at the customer's SCM (default ownership: the customer
   hosts this repo; the consultant is a contributor, not the owner).
3. Replace every placeholder in `group_vars/all.yml` with the customer's real
   values.
4. Replace the placeholder hostnames in `hosts.yml` with the customer's real
   ones — same groups as the lab (`foreman`, `misc`,
   `keycloak`, `kc_pgsql`, `dns_nodes`, `nut_server`/`nut_client`,
   `proxmox_ve`, `syslog`, `ipa`, `gitlab`, `gitlab_runner`, `harbor`,
   `webproxy`, `vsftp`, `ftp_lb`) if this engagement uses the same
   deployments, otherwise add or remove groups/hosts to match what's
   actually being delivered. `building` isn't a static group — see "Dynamic
   build-network source" below if this engagement needs it.
5. Add `group_vars/<group>.yml` and `host_vars/<hostname>.yml` as needed for
   per-service-role or per-host facts (firewall ports, etc.).

Deployment repos (`harden`, etc.) never change between engagements — they're
pure code with no inventory of their own, so the same deployment repo runs
against this customer's inventory just by pointing at it as a second
inventory source, the same way it would against the lab's `inventory-common`.


What belongs here — the tier rule
----------------------------------

Ask: *would this value still be correct if a completely different deployment
ran against this host?*

- **Yes, and it's the same for every host** → `group_vars/all.yml`
- **Yes, but it varies by what the host runs** → `group_vars/<group>.yml`, or
  `host_vars/<hostname>.yml` for something specific to one host — e.g.
  firewall ports
- **No, only relevant because a specific deployment is running** (hardening
  tuning, package lists, anything role-specific) → stays in that deployment's
  own `inventory/`, never here

This repo owns host and group *definition*. A deployment's own local
inventory may add *vars* to a group/host defined here, but must never define
a host or group itself — keeps merging multiple inventory sources safe with
no overwrite-order ambiguity.


Consuming this from a deployment
---------------------------------

**Manual / CI**: clone this repo alongside the deployment repos and pass both
as inventory sources — adjust the relative depth to wherever each is
actually checked out (for a deployment under `deployments/<name>/` with this
repo as a sibling of `deployments/`, that's `../../`, matching
`inventory-common`'s layout in the lab):

```
ansible-playbook -i inventory/ -i ../../inventory-<client>/hosts.yml site.yml
```

or via `ansible.cfg` — **comma-separated**, not colon:

```ini
[defaults]
inventory = inventory/,../../inventory-<client>/hosts.yml
```

Point at `hosts.yml`, not the directory: a directory source is parsed
recursively and would load every `instances/` directory at once. The file
source still picks up the adjacent `group_vars/` and `host_vars/`.

**AWX**: one Inventory object per deployment, with two SCM Inventory Sources
— this repo (source path `hosts.yml`, not the directory), and the
deployment's own Project pointed at its local `inventory/` subdirectory. Leave **Overwrite** and **Overwrite Variables**
unchecked on both sources (the default) so neither sync can delete what the
other defined; enable **Update on Launch** so a stale cached inventory isn't
used. The deployment's Job Template points its Inventory field at this
combined Inventory object, not either Project's raw checkout.


Multiple instances
-------------------

A service that runs more than once (several k8s clusters, one per
environment) gets one directory per instance under
`instances/<service>/<name>/`, and its hosts stay out of the root `hosts.yml`.
Start by copying `instances/k8s/example/` and renaming `k8s_example` to
`k8s_<name>` in `hosts.yml` and `group_vars/`.

```
instances/<service>/<name>/
├── hosts.yml                    # only this instance's hosts
└── group_vars/
    ├── <service>_<name>/        # instance_name + this instance's vars
    └── <role group>/            # optional, e.g. k8smasters/keepalived.yml
```

Rules:

1. Load exactly one instance per run. Ansible merges every loaded source into
   one group, so two loaded at once mix their nodes and vars.
2. List each node in the instance group (`k8s_<name>`) and again in its role
   group (`k8smasters`/`k8sworkers`). Don't nest role groups under the
   instance group.
3. Put `instance_name` and instance-specific vars in
   `group_vars/<service>_<name>/`, never on the shared group (`k8s`) — a var
   on the shared group is overwritten by whichever instance loads last.
   Facts every instance shares stay in the root `group_vars/<group>.yml`.
4. Use underscores in group names (`k8s_prod_a`). Name instances
   `<env>_<set>` (`dev_a`, `prd_b`) where a service runs in several
   environments.
5. Secrets point at a per-instance Vault path. Never a literal.

**Per-instance deployments** (`k8s`, `k8s-platform`): the deployment's
`ansible.cfg` builds the path from an env var, and its first play runs
`mgcdrd.infrabase.instance_guard`, which fails if no instance, or more than
one, is loaded:

```ini
inventory = inventory/,../../inventory-<client>/hosts.yml,../../inventory-<client>/instances/k8s/${DEPLOY_INSTANCE}
```

```
DEPLOY_INSTANCE=prd_a ansible-playbook site.yml
```

**Fleet deployments** (`harden`, `vm-migrate`, `proxmox-vm-manage` — `hosts: all`)
source `fleet-env.sh` from the deployment directory, which appends every
instance directory to that deployment's inventory. Edit nothing per instance.

```
source ../../inventory-<client>/fleet-env.sh             # every instance
source ../../inventory-<client>/fleet-env.sh dev         # dev and dev_*
source ../../inventory-<client>/fleet-env.sh prd_a       # one instance...
ansible-playbook site.yml --limit k8s_prd_a              # ...limited to its group
```

Without the script a fleet run silently skips every instance host, and
without `--limit` a fleet run also covers every host in the root `hosts.yml`.
Check with `--list-hosts` first. Under AWX, skip the script and add each
instance as an inventory source. The lab's own `inventory-common/README.md`
has the full rationale and the gotchas.


Dynamic build-network source
------------------------------

`build.foreman.yml` is a third inventory source — not a directory, a
`theforeman.foreman.foreman` plugin config file that queries Foreman for
hosts on its "Build" subnet and drops them into a `building` group (the
same group `group_vars/building.yml` wires up for SSH ProxyJump through
Foreman). If this engagement's Foreman gateways a NAT'd build network the
same way, add it as a third comma-separated `-i` in the consuming
deployment's `ansible.cfg`:

```ini
[defaults]
inventory = inventory/,../../inventory-<client>/,../../inventory-<client>/build.foreman.yml
```

and add `theforeman.foreman` to that deployment's `collections/requirements.yml`.

This plugin does not template its own config file, so credentials aren't in
`build.foreman.yml` — source `foreman-inventory-env.sh` (Vault-backed,
requires a dedicated read-only Foreman user — see that script's header)
into your shell first. Under AWX, use its built-in Foreman/Satellite
inventory source type instead and skip this file entirely.

If this engagement doesn't use a NAT'd build network, delete
`build.foreman.yml`, `foreman-inventory-env.sh`, and `group_vars/building.yml`,
and don't add the third `-i` source or collection dependency.
