inventory-template
===================

Skeleton for a new customer engagement's inventory repo. Clone or fork this,
push it to the customer's own SCM, and fill in the placeholders. Don't branch
or fork `inventory-common` itself, since that has the lab's real topology in it.

One repo per customer, one directory per environment. The number and names of
environments depend on the customer (`dev`, `prd`, or `sbx`/`dev`/`stg`/`prd`).
Each environment directory is self-contained: its own hosts, its own variables,
nothing shared with its siblings.

```
inventory-<client>/
├── dev/                      # copy of example/, one per environment
│   ├── hosts.yml
│   ├── group_vars/
│   └── host_vars/
└── prd/
```

`example/` is the skeleton to copy:

```
example/
├── hosts.yml                 # service groups with example.com placeholder hosts
├── build.foreman.yml         # optional dynamic source: hosts on Foreman's "Build" subnet
├── foreman-inventory-env.sh  # Vault-backed FOREMAN_URL/USER/PASSWORD for build.foreman.yml
├── group_vars/
│   ├── all/                  # environment constants, hardening policy, proxmox + vm-migrate settings
│   ├── <group>/              # one directory per service group: that service's role variables
│   └── <group>.yml           # small groups with a single file (keycloak, ipa, syslog, building)
└── host_vars/                # worked examples for hosts with host-specific facts
```

The shape matches the lab's real `inventory-common/lab`: same group names, same
keys, placeholder values. Adding or removing groups once the placeholders are
swapped is fine; the shape is a starting point.

Variables are the role's own names (`ipa_server_domain`, `nginx_server_blocks`,
`keepalived_vrrp_instances`, ...). There are no deployment-only wrapper
variables. To add to a base list rather than replace it, use the
`<var>_extra_<suffix>` form the roles support (`sshd_match_blocks_extra_*`,
`storage_mounts_extra_*`, `storage_disks_extra_*`, `firewall_zones_extra_*`).


Starting a new engagement
--------------------------

1. Clone or fork this repo and rename it `inventory-<client>`.
2. Point its remote at the customer's SCM (the customer owns the repo; the
   consultant is a contributor).
3. For each environment: `cp -r example <env>`.
4. In `<env>/group_vars/all/all.yml`, replace every placeholder with the
   customer's values, including `vault_kv_env` (the Vault path prefix for that
   environment).
5. In `<env>/hosts.yml`, replace the placeholder hosts. Keep the same groups if
   the engagement uses the same deployments; otherwise add or remove groups to
   match what's being delivered. `building` isn't a static group (see
   "Dynamic build-network source").
6. Fill in `<env>/group_vars/<group>/` for the services being delivered and
   delete the directories for services that aren't.
7. Run any deployment against one environment:
   `ansible-playbook -i ../../inventory-<client>/dev/hosts.yml site.yml`

Deployment repos (`harden`, `k8s`, ...) never change between engagements. They
hold no inventory, so the same code runs against any environment directory.


Where a variable goes
----------------------

Everything lives in the environment directory. Pick the narrowest scope that is
correct for every host in it; narrower scopes override wider ones:

| Scope | Location |
|---|---|
| Every host in the environment | `group_vars/all/` |
| Every host that runs a service | `group_vars/<group>/` |
| A service that spans several groups (ftp, infra_kc) | `group_vars/<parent group>/`, where the parent group lists the others as children in `hosts.yml` |
| One host | `host_vars/<fqdn>/` |

Secrets are set directly on the role variable as a
`community.hashi_vault.vault_kv2_get` lookup against
`<vault_kv_infra_mount>/<vault_kv_env>/<secret>`. Never a literal.

Run with `-i <env>/hosts.yml`, not the directory. A directory source is parsed
recursively and would try to load `build.foreman.yml` and the `.sh` helper as
inventories. Group and host variables still load from the `group_vars/` and
`host_vars/` next to `hosts.yml`.


More than one of a service (a second k8s cluster, a second proxy pair)
-----------------------------------------------------------------------

Give it its own environment directory, or its own differently named groups in
the same directory. There is no per-service instance mechanism; running against
one environment means exactly one set of hosts, so nothing can mix.

The playbooks target the fixed role groups (`k8smasters`, `k8sworkers`,
`webproxy`, ...), so a second cluster in the same directory needs its own
`group_vars` and a `--limit`. Separate environment directories are simpler.


AWX
---

One Inventory per environment with one SCM Inventory Source: this repo, source
path `<env>/hosts.yml`. Leave Overwrite and Overwrite Variables unchecked and
enable Update on Launch.


Dynamic build-network source
------------------------------

`build.foreman.yml` is a `theforeman.foreman.foreman` plugin config that
queries Foreman for hosts on its "Build" subnet and puts them in a `building`
group (the group `group_vars/building.yml` wires up for SSH ProxyJump through
Foreman). If the engagement's Foreman gateways a NAT'd build network the same
way, add it as a second comma-separated inventory in the consuming deployment's
`ansible.cfg`:

```ini
[defaults]
inventory = ../../inventory-<client>/dev/hosts.yml,../../inventory-<client>/dev/build.foreman.yml
```

and add `theforeman.foreman` to that deployment's `collections/requirements.yml`.

The plugin doesn't template its own config, so credentials aren't in the file.
`source foreman-inventory-env.sh` (Vault-backed, needs a dedicated read-only
Foreman user; see the script header) before running. Under AWX, use the
built-in Foreman inventory source type instead.

If the engagement has no NAT'd build network, delete `build.foreman.yml`,
`foreman-inventory-env.sh` and `group_vars/building.yml`.
