inventory-template
===================

Skeleton for a new customer engagement's inventory repo. Clone or fork this,
push it to the customer's own SCM, and fill in the placeholders — don't
branch or fork `inventory-common` itself, since that has the lab's real
topology in it.

```
inventory-template/
├── hosts.yml            # mirrors inventory-common's real group structure, example.com placeholder hosts
└── group_vars/
    ├── all.yml           # mirrors inventory-common's real keys, example.com placeholder values
    ├── k8s.yml           # real k8s-cluster-wide facts (version, CIDRs, OIDC, vault_ext_fqdn)
    ├── keycloak.yml      # real keycloak/postgres hostnames + keepalived VIP
    ├── nut_server.yml    # firewall_zones for the UPS-attached host
    ├── ftp_lb.yml        # firewall_zones for the haproxy-lb group
    ├── vsftp.yml         # firewall_zones for the vsftp group
    └── webproxy.yml      # firewall_zones for the webproxy group
```

Every file has the *same shape* as the lab's real `inventory-common` —
same group names, same nesting, same host counts, same keys — so starting
an engagement is replacing values, not guessing what groups or files to
add. Add or remove groups/hosts/files freely once you're past the initial
placeholder swap; the shape is a starting point, not a requirement.

`host_vars/` isn't included — add it as the engagement's real hosts need
host-specific facts.


Starting a new engagement
--------------------------

1. Clone or fork this repo, rename it `inventory-<client>`.
2. Point its remote at the customer's SCM (default ownership: the customer
   hosts this repo; the consultant is a contributor, not the owner).
3. Replace every placeholder in `group_vars/all.yml` with the customer's real
   values.
4. Replace the placeholder hostnames in `hosts.yml` with the customer's real
   ones — same groups as the lab (`foreman`, `misc`, `k8s`, `keycloak`,
   `kc_pgsql`, `dns_nodes`, `nut_server`/`nut_client`, `proxmox_ve`,
   `syslog`, `ipa`, `gitlab`, `gitlab_runner`, `harbor`, `webproxy`,
   `vsftp`, `ftp_lb`) if this engagement uses the same deployments,
   otherwise add or remove groups/hosts to match what's actually being
   delivered.
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
ansible-playbook -i inventory/ -i ../../inventory-<client>/ site.yml
```

or via `ansible.cfg` — **comma-separated**, not colon:

```ini
[defaults]
inventory = inventory/,../../inventory-<client>/
```

**AWX**: one Inventory object per deployment, with two SCM Inventory Sources
— this repo, and the deployment's own Project pointed at its local
`inventory/` subdirectory. Leave **Overwrite** and **Overwrite Variables**
unchecked on both sources (the default) so neither sync can delete what the
other defined; enable **Update on Launch** so a stale cached inventory isn't
used. The deployment's Job Template points its Inventory field at this
combined Inventory object, not either Project's raw checkout.
