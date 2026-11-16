# Local build cleanup

This is repository maintenance with no runtime, application version, data format,
or permission changes. Role checks and application UI are outside its scope.

`build/` is ignored by Git. It holds disposable exports and isolated check
projects, alongside local evidence and explicitly retained qualified packages.
The retention decisions and their reasons have one owner:
[`tools/build-retention.json`](../tools/build-retention.json). Unknown directories
are preserved automatically. Add a directory to `retired` only after reviewing
its purpose and removing any `retained` entry for it.

Use PowerShell 7 (`pwsh`) to support the existing long asset paths. Preview from
the repository root:

```powershell
pwsh -NoProfile -File tools/clean_build.ps1
```

Apply the reviewed policy:

```powershell
pwsh -NoProfile -File tools/clean_build.ps1 -Apply
```

Before deleting any retired directory, the helper copies and SHA-256 verifies
its evidence into `build/_archive/<timestamp>-<id>/directories/<original-name>/`.
Loose logs and helper scripts move into that archive's `root/` folder. Run an
archived helper from the repository root if it depends on the working directory.
Source-check snapshots are preserved except for disposable `.godot` caches.
Only binary/model payloads identified in a retired package's receipt are omitted
from its archive; its receipt, diagnostics, notices and other files are retained.
The archive is evidence, not a complete backup of retired executable packages.

Each archive's `manifest.json` records original directory names, evidence hashes,
discarded package payload receipt hashes and completion state. Qualification
facts continue to live in `docs/audit/`; cleanup does not rewrite those historical
records or claim that deleted packages are still installed. Archives are local
and ignored by Git, so copy them separately if they need long-term retention.

The helper rejects links/junctions and paths outside `build`, refuses to remove
directories used by an active Windows process, and checks for concurrent file
changes before deletion. Preview is the default. A `build/.gdignore` marker keeps
generated projects and archived snapshots out of the main Godot asset scan.

The 2026-11-16 review preserves the local release/rollback packages and latest
source-check workspace listed in the policy. Newer Solid/Fast packages under
`F:\PXRFusion-builds` are outside this cleanup, as are source assets, private
models, user compositions, editor state and runtime user data outside `build`.
