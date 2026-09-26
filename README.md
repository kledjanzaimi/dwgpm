# DWG Project Manager

Role-based project folders for engineering teams. The filesystem stays the
source of truth: AutoCAD reads drawings and the shared library natively off a
read-only share, and every write goes through this app.

## The one-paragraph architecture

Each company runs its **own isolated instance** — own database, own file root,
own admin. There is no multi-tenancy, deliberately. Inside an instance, one
project is one directory tree, generated from a template. Roles are per-project
(a person can be a project manager on one and a plain user on another); admin is
the single global exception.

**Reads** go direct: workstations mount each project as a read-only SMB share, so
AutoCAD resolves relative xrefs to `_Library` at native speed.
**Writes** go through the app: the share refuses writes, so every upload and
delete passes `Permissions.can?` and lands in the audit log. That split is the
whole design.

## Layout

```
app/lib/permissions.rb       can? — the entire authorization model
app/lib/folder_template.rb   loads YAML, resolves nearest rule (inheritance)
app/lib/safe_path.rb         confines every path to the project root
app/services/project_scaffolder.rb   template -> real directories
app/controllers/files_controller.rb  resolve -> authorize -> act -> audit
config/templates/*.yml       structure + permissions, editable without deploy
```

Four tables: `users`, `projects`, `memberships`, `audit_logs`. No per-folder
rows — permissions come from the template.

## Install

```bash
cp .env.example .env      # the only file that changes per company
$EDITOR .env
touch "${STORAGE_ROOT_HOST}/.dwgpm-root"   # only on a fresh storage root
mkdir -p data                             # SQLite; must be owned by uid 1000
docker compose up -d --build              # migrates the database on start
docker compose exec app bin/rails admin:seed
```

Open `https://${APP_HOST}`. Caddy serves it with its own internal certificate;
import Caddy's root certificate on workstations (see `Caddyfile`) to drop the
browser warning.

For development without Docker: `bin/setup --skip-server`, then `bin/rails test`
or `bin/rails server`.

Then export the shares (Samba example, one per project, **read-only**):

```ini
[proj_acme-123$]
   path = /srv/projects/acme-123
   read only = yes
   valid users = @proj_acme-123
```

Per-project shares are what keep view isolation: a user only mounts the projects
they're a member of. Add a hook to your user provisioning to manage the
`@proj_<slug>` group when a PM adds or removes a member — or run the shares
manually while there are few projects.

## Permissions

Edit `config/templates/standard_v1.yml`. A rule applies to its folder and
everything beneath it, so `01_Incoming/clientX/` inherits `01_Incoming`
automatically.

- **Editing a rule** applies to all existing projects immediately.
- **Adding a folder** needs `bin/rails projects:resync_all` to appear in
  projects that already exist.

Undefined paths grant nothing. Admin is implicitly everything, everywhere.

## Two things that will bite you

**1. Relative xrefs bake in depth.** `..\..\_Library` only resolves if the
drawing sits exactly two levels down. Defend it twice: keep `dwg_depth: 2` in
the template and set AutoCAD's **Project Files Search Path** to the library on
each workstation. The search path is a fallback that rescues you when a drawing
gets moved, when depth drifts, or when a company mounts things differently.
Cheap to set, saves real pain.

**2. A DWG must be opened from its real position.** Downloading it into
`Downloads\` breaks every relative reference. That is why the dashboard shows
**Copy path to open** for DWGs instead of a download button: it hands back the
UNC path, and AutoCAD opens the drawing in place. Non-DWG files download
normally.

If you want one-click opening, register a custom protocol handler
(`dwgpm://open?path=...`) on the workstation image and have it shell out to
`acad.exe`. Worth it once users complain about pasting; not before.

## Library: frozen or shared?

Default is `mode: copy` — the library is copied into each project at creation,
so a project reopened in three years renders the way it was drawn. Library
updates reach it only when you choose:

```bash
bin/rails projects:sync_library[acme-123]
```

Switch to `mode: link` for one master library that updates everywhere at once.
Faster to maintain, but a block change silently alters closed projects. For
engineering deliverables, copy is usually the right instinct.

## Maintenance

```bash
bin/rails projects:check          # verify every tree matches its template
bin/rails projects:resync_all     # create folders added to a template later
```

Back up `${STORAGE_ROOT}` and `./data/production.sqlite3` together — the tree is
the data, the database is only permissions and history.

## Notes on choices

- **SQLite, not Postgres.** A handful of users on an intranet never needs more,
  and it removes a service from the install. `DATABASE_URL` swaps it later.
- **`has_secure_password`, not Devise.** Fewer moving parts to read. Devise is a
  clean drop-in if you want password reset and lockout without writing them.
- **Auth is local accounts.** Add an LDAP bind behind an env toggle for
  companies that run AD: authenticate against AD, keep authorizing here.
