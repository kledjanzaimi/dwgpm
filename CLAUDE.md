# CLAUDE.md

Role-based project folders for engineering teams using AutoCAD. Read `README.md`
for the architecture and the reasoning; this file is the short list of things
that must not be broken.

## Hard invariants

These are load-bearing. Each one looks like it could be simplified, and each
simplification breaks something real. **Ask before violating any of them.**

1. **The filesystem is the source of truth.** AutoCAD reads drawings directly.
   Never move file storage into the database or object storage.

2. **Reads bypass the app; writes go only through the app.** Workstations mount
   each project **read-only** over SMB so AutoCAD resolves xrefs natively. The
   mount must stay read-only — that is what forces every mutation through
   `Permissions.can?` and the audit log. Making it read-write to "simplify
   uploads" destroys the entire enforcement model.

3. **Every filesystem operation follows: `SafePath.resolve` → `Permissions.can?`
   → act → `AuditLog`.** No new action may skip a step.

4. **`SafePath` must use `realpath`.** A string prefix check passes the obvious
   `../` tests and silently allows escape via symlink. Do not "optimize" it.

5. **Fail closed.** `nearest_rule` returning nil means deny. Never default to
   permit for undefined paths.

6. **DWG files are located, never downloaded.** `FilesController#locate` returns
   a UNC path; the drawing opens in place. A DWG downloaded to `Downloads\` has
   every relative xref to `_Library` broken. Do not add a download button for
   `.dwg`.

7. **Relative xrefs bake in depth** (`..\..\_Library`). `dwg_depth: 2` in the
   template is a contract with every existing drawing. Changing where DWGs live
   breaks drawings already on disk.

8. **No multi-tenancy.** One isolated instance per company: own DB, own file
   root, own admin. Do not add a `tenant_id`.

9. **Permissions live in `config/templates/*.yml`, not in code or the DB.** Do
   not add per-folder permission rows. The template is the single source of
   truth for both structure and access.

10. **Roles are per-project** via `memberships`. `users.global_admin` is the one
    global role. A PM may only assign `user` / `supervisor`, only on their own
    projects.

11. **`audit_logs` is append-only.** No updates, no deletes.

12. **Intranet only.** The proxy binds to `LAN_BIND_IP`, never `0.0.0.0`.

13. **SQLite stays on the VM's local disk** (`./data`), never on the CIFS mount.
    SQLite locking over SMB is unreliable and corrupts. Do not "tidy" the
    database onto the share so it gets backed up — back it up with
    `sqlite3 .backup` instead (see `WINDOWS-DEPLOY.md`).

14. **Never write to `STORAGE_ROOT` without the `.dwgpm-root` marker.** An
    unmounted CIFS share is an empty local directory, not an error — the app
    would silently scaffold onto disposable disk.
    `config/initializers/storage_root_check.rb` enforces this. Do not remove it
    to make local development easier; touch the marker instead.

## Deployment reality

Production is a **Windows file server** (holds the tree, exports read-only
per-project SMB shares, one read-write share to the service account) plus a
**disposable Hyper-V Linux VM** running this app over a CIFS mount. Docker
Desktop is not supported on Windows Server and LCOW is deprecated, so the VM is
the supported route, not a workaround. Full setup in `WINDOWS-DEPLOY.md`.

Consequences to keep in mind when changing code:

- **Case-insensitive filesystem.** `nearest_rule` matches exactly, so
  `00_admin/x.dwg` resolves on NTFS but matches no rule and is denied.
  Fail-closed makes this a usability wart, not a hole — canonicalize against
  on-disk casing rather than loosening the match.
- **`mkdir_p(mode: 0o770)` is a silent no-op over CIFS.** NTFS ACLs govern.
  Never rely on that mode meaning anything.
- **Library `mode: link` cannot work** (symlinks over CIFS). `copy` only.
- AD exists at these sites; LDAP bind for authentication is wanted and not yet
  built. Authenticate against AD, keep authorizing here.

## Map

```
app/lib/permissions.rb       can? — the entire authorization model
app/lib/folder_template.rb   loads YAML, nearest_rule = permission inheritance
app/lib/safe_path.rb         confines every path to the project root
app/services/project_scaffolder.rb   template -> real directories on disk
app/controllers/files_controller.rb  the guarded pipeline
config/templates/*.yml       structure + permissions, edited without deploy
```

Four tables: `users`, `projects`, `memberships`, `audit_logs`.

## Status

Runs on Ruby 3.4 / Rails 8.1 / SQLite, in Docker behind Caddy. `bin/rails test`
covers the resolver, path guard, permissions and the controller pipeline
(login, scaffold, upload, locate, delete, traversal, membership rules).

Development without Docker uses `tmp/projects` as the storage root
(`config/environments/development.rb`); `bin/setup` creates its marker.

Not built yet: LDAP authentication, password reset, the `dwgpm://` protocol
handler, and on-disk case canonicalisation for `nearest_rule`.

## Commands

```bash
bin/rails test                    # run the test suite
docker compose up -d --build      # entrypoint runs db:prepare on start
docker compose exec app bin/rails admin:seed
bin/rails projects:check          # verify trees match templates
bin/rails projects:resync_all     # create folders added to a template later
bin/rails projects:sync_library[slug]
```

## Conventions

- Prefer minimal, scoped changes over broad refactors.
- `.env` is per-company and never committed. `.env.example` is the template.
- Editing a permission rule applies to all projects immediately; adding a folder
  to a template needs `projects:resync_all`.
