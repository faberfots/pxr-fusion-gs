# Attribution and licensing

PXRFusion is developed by POLYGONICS SAS on the foundation of Ethan Truong's (2Retr0) [GodotGaussianSplatting](https://github.com/2Retr0/GodotGaussianSplatting). The original project provides the Gaussian splatting implementation from which this application evolved. Its copyright and MIT terms remain in the root `LICENSE`; a separate original notice is retained at `provenance/GodotGaussianSplatting-LICENSE.txt`.

POLYGONICS SAS's notice covers its owned original additions and modifications. It does not transfer ownership of upstream contributions. Existing contribution history is preserved. The exact originally imported GS Git revision is unknown; identifying the project and matching its licence does not establish an imported commit. See `provenance/project-origins.json`.

Subsequent application development includes mixed GS/native scenes, composition persistence, transform/collision workflows, loading improvements, the Polygonics interface and Cortex/SpatialOS integrations. These descriptions identify application enhancements; they do not claim authorship of the underlying engine, original GS implementation, research, algorithms, libraries or model weights.

Runtime transformation tools use Christopher Charbonneau's (chrisizeful) MIT-licensed [Gizmo3D](https://github.com/chrisizeful/Gizmo3D), itself derived from Godot editor C++ code. The port's own MIT notice, Godot notice, pinned revision, original hashes and local modification hashes remain under `addons/Gizmo3DScript`. This is a runtime port; exported applications do not instantiate the editor-only C++ viewport tool.

## Responsibilities and source of truth

| Record | Responsibility |
|---|---|
| Root `LICENSE` | MIT terms and retained original/company copyright notices |
| Original component licence files | Authoritative retained terms for those components |
| `docs/dependency-inventory.json` | Component identity, authors, source, revision evidence, notice paths and unresolved provenance |
| Generated `CREDITS.md` | Readable attribution and contribution context |
| Generated `THIRD_PARTY_NOTICES.txt` | Full available notices; identical text can be referenced once with aliases |
| Generated `assets/legal` | Same credit and notice projections used by the app |
| `docs/archive/upstream-README.md` | Preserved historical upstream description, research and demo credits |

Run `python tools/generate_credits.py` after an inventory or notice change; `--check` detects stale projections. Generated notice text hashes use UTF-8/LF so source checkouts on different operating systems agree. Original retrieved notice files and their provenance remain separate. Vendor byte hashes are preserved by `.gitattributes`.

The app exposes credits through Workspace settings → About & licences. Credits load when opened; the full licence tab loads only when explicitly selected. Godot's actual running copyright and licence APIs provide engine-specific notices. Export packaging verifies generated files and includes the root licence, credits, third-party notices and retained dependency licence files.

MIT applies to the project code within its stated scope. Third-party dependencies, fonts, models, weights and artwork retain their own licences. In particular, the SAM3 model pack is not relabelled MIT. Available notices are evidence of terms; they do not resolve missing asset ownership or redistribution provenance. These remaining gaps are recorded in the inventory and audit.

## Publication

Repository descriptions, README, commit descriptions and release notes identify the original foundation and distinguish subsequent enhancements. Original authorship is retained. Existing projects are credited by their actual names and URLs; attribution does not imply upstream endorsement. GitHub publication retains the repository's current visibility. Models, runtime binaries, credentials and private datasets continue to follow the existing exclusion policy.

The MIT licence permits reuse, modification and commercial distribution while requiring its copyright and permission notices to accompany covered software. See [the MIT text](https://opensource.org/license/mit) and [Godot's licence-compliance guidance](https://docs.godotengine.org/en/stable/about/complying_with_licenses.html).
