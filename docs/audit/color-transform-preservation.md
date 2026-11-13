# Color and transform preservation contract

Baseline: commit 14831fd, qualified desktop source commit 64ce36c. Active editor UID rewrite is preserved.

Preserve full PLY/GSRES populations with no byte-size gate, atlas accounting and migration, multiple model identity, independent Node3D Transform3D, XYZ numeric controls, visibility/deletion, camera navigation/focus/picking, UI shielding, provider role/consent policy, native inference and source-free export.

Change requested: remove selection-induced color cast; add independent color presets/controls and original comparison; add simple direct model selection/translation/rotation/scaling using the existing model transform. Keep color preference separate from quality settings. Qualify only after actual Godot compilation, failing-before/passing-after color evidence, mouse interaction/GUI/persistence tests, relevant existing rendering/lifecycle checks and rendered UI inspection.

Remaining audit findings retain status until their capabilities and required evidence actually exist. Provider revocation, authenticated-provider qualification and asset ownership cannot be fabricated by application changes.

Rollback reference: preserved baseline commit and unchanged active files until candidate qualification.
