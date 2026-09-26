# Deploying on Windows infrastructure

The company's Windows file server keeps the project tree. A small Linux VM runs
the app and mounts that tree. Two machines, two jobs.

Docker Desktop is not supported on Windows Server, and Linux Containers on
Windows (LCOW) is deprecated — so there is no path to running this app directly
on a Windows Server host. A Hyper-V Linux VM is the supported route, not a
workaround.

The VM holds **no project data** — only SQLite and `.env`. Rebuild it whenever
you like. That is the point of this layout.

```
Workstations ──read-only SMB──> Windows file server <──read-write CIFS── Linux VM (app)
     │                            D:\Projects\<slug>                         │
     └──────────────────── HTTPS (uploads, deletes) ───────────────────────>─┘
```

## 1. Windows file server

One service account writes. Everyone else reads. That split is what makes the
app the only write path — enforced by NTFS rather than by trust.

Create `svc_dwgpm` (a normal AD service account, no interactive logon), then:

```powershell
New-Item -ItemType Directory -Path D:\Projects

# The app's private door. Service account only — users must never reach this.
New-SmbShare -Name "projects$" -Path D:\Projects -FullAccess "ACME\svc_dwgpm"

$acl = Get-Acl D:\Projects
$acl.SetAccessRuleProtection($true, $false)   # stop inheriting looser parent ACLs
$acl.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule(
  "ACME\svc_dwgpm","Modify","ContainerInherit,ObjectInherit","None","Allow")))
$acl.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule(
  "ACME\Domain Admins","FullControl","ContainerInherit,ObjectInherit","None","Allow")))
Set-Acl D:\Projects $acl
```

Then the marker the app checks for before it will start (see step 3):

```powershell
New-Item -ItemType File -Path D:\Projects\.dwgpm-root
```

### Per-project share

Run this for each project after the app scaffolds it. `Read` at **both** the
share and NTFS level — share permissions alone are not enough.

```powershell
param($slug)   # e.g. acme-123

New-ADGroup -Name "proj_$slug" -GroupScope Global -Path "OU=Projects,DC=acme,DC=local"

New-SmbShare -Name "proj_$slug`$" -Path "D:\Projects\$slug" `
             -ReadAccess "ACME\proj_$slug"

$acl = Get-Acl "D:\Projects\$slug"
$acl.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule(
  "ACME\proj_$slug","ReadAndExecute","ContainerInherit,ObjectInherit","None","Allow")))
Set-Acl "D:\Projects\$slug" $acl
```

Membership of `proj_<slug>` is what a user mounts. When a PM adds someone in the
app, mirror it: `Add-ADGroupMember -Identity proj_acme-123 -Members jsmith`.
Script this once and project setup stops being manual.

## 2. Linux VM

Hyper-V, Ubuntu Server LTS, 2 vCPU / 4 GB / 40 GB. Docker + Compose, nothing else.

```bash
# /etc/dwgpm-smb.cred   (chmod 600, root-owned)
username=svc_dwgpm
password=...
domain=ACME
```

```
# /etc/fstab
//fileserver/projects$  /srv/projects  cifs
  credentials=/etc/dwgpm-smb.cred,uid=1000,gid=1000,file_mode=0660,dir_mode=0770,vers=3.1.1,_netdev,nofail  0 0
```

`nofail` lets the VM boot when the file server is down — which introduces the
hazard step 3 closes.

## 3. The unmounted-mount hazard

If the CIFS mount fails, `/srv/projects` is not an error. It is an **empty local
directory**, and the app will cheerfully scaffold projects onto the VM's
disposable disk and report success. Users then upload real work into a folder
nobody backs up.

Close it twice:

```bash
# 1. Make the bare mountpoint unwritable, so a failed mount fails loudly.
sudo mkdir -p /srv/projects
sudo chattr +i /srv/projects        # mounting over an immutable dir still works

# 2. The app refuses to boot without the marker file (config/initializers/
#    storage_root_check.rb). Add a compose healthcheck to catch a mid-run drop:
#    test: ["CMD", "test", "-f", "/srv/projects/.dwgpm-root"]
```

The marker lives on the **file server**, so it can only be visible when the
mount is genuinely up.

## 4. Configure and run

```bash
cp .env.example .env
```

```ini
STORAGE_ROOT_HOST=/srv/projects
STORAGE_ROOT=/srv/projects
UNC_TEMPLATE='\\fileserver\proj_%{slug}$'
SHARE_TEMPLATE='proj_%{slug}$'
LAN_BIND_IP=10.0.0.5
```

```bash
docker compose up -d
docker compose exec app bin/rails db:migrate admin:seed
```

## 5. Backups

The tree is already covered by whatever backs up `D:\Projects` — that is the
main reason to keep it on their file server. Only the database is yours:

```bash
# nightly cron on the VM. Never copy the live SQLite file; use .backup.
sqlite3 /srv/data/production.sqlite3 ".backup '/tmp/db.bak'"
mv /tmp/db.bak "/srv/projects/.dwgpm-backups/$(date +%F).sqlite3"
```

Writing it under the storage root means their existing backup picks it up. The
slug format forbids a leading dot, so `.dwgpm-backups` can never collide with a
project.

To rebuild the VM: new Ubuntu VM, restore `.env` + `/etc/dwgpm-smb.cred`,
`git clone`, restore the newest `.sqlite3`, `docker compose up -d`. Nothing else
is on it.

## Windows-specific gotchas

**SQLite must stay on the VM's local disk.** Its locking over SMB is unreliable
and will corrupt the database. Keep it in `./data`; never "tidy" it onto the
share.

**AutoCAD opens drawings read-only, and that is correct.** Users see the
read-only warning, then Save As locally and upload through the app. Say this
during rollout or you will answer it weekly.

**Case-insensitivity.** `nearest_rule` matches folder names exactly, so
`00_admin/x.dwg` resolves fine on NTFS but matches no rule and is **denied**.
Fail-closed means this is a usability wart, not a hole — but canonicalize
against on-disk casing and test it.

**`mkdir_p(mode: 0o770)` is a silent no-op over CIFS.** NTFS ACLs govern.
Harmless, but never rely on that mode meaning anything.

**Library `mode: link` will not work.** Symlinks over CIFS are a mess. Stay on
`copy` — the default, and the better choice regardless.

## Worth doing here

They run AD, so authenticate against it rather than keeping a second password
list: LDAP bind for authentication, roles still assigned in this app. Not built
yet — see `CLAUDE.md`.
