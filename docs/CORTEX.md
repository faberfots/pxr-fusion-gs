# Cortex: configuration, local inference and portable resources

The existing `CognitivePanel.tscn` is the single Cortex entry point. It retains the shared Polygonics theme, compact scale, transparency and draggable header. UI controls are authored in the scene; GDScript binds them to services. There is no second settings window or Python application runtime.

## Start with your goal

Open Cortex and choose **What would you like to do?** The default is **Select with a click**, which needs no account. Expand **Guide** for the steps, privacy and limitations in plain language; collapse it to make more room for your scene and conversation.

| Preset | What you can do |
|---|---|
| Select with a click · recommended | Capture the view, click an object, find its highlighted area, then select its imported model. Uses MobileSAM locally. |
| Find by description | Capture the view and type `person`, `motorcycle` or another short description. An optional box narrows the search. Uses the included SAM3 locally. |
| Understand my scene · private | Ask about visible model names, positions and layout. The included Qwen starts from **Start & ask privately**; it reads scene information without an image or cloud upload. |
| Explain my selected model · private | Ask about the selected model's scene information. Select a model first. |
| Ask my connected assistant | Choose your saved connection and review sharing permissions. An account key may be needed; an enabled vision model can discuss a shared picture. |
| Advanced / my own settings | Use the original Ask, Select and Setup tabs with your own settings and optional scene commands. |

Guided presets never grant scene-editing commands. Choosing a preset or opening Cortex does not start a model. The explicit private Ask button authorizes the fixed bundled assistant to read scene information on this computer, then prepares it automatically. Cancel stops the pending question even if model startup is still finishing.

Goal and help preferences live in `user://cortex/experience.json`, owned by `CortexSettings`. The existing `settings.json` document, credentials and advanced settings are preserved. Guided request settings are derived from the preset catalog; choosing Advanced restores the saved configuration. Older qualified applications can still read the unchanged settings schema.

Selection presets select whole imported 3D GS models. A highlighted person inside a single environment scan does not become a separately editable Gaussian model. Private Qwen presets read structured scene information and do not see the rendered picture. These limits are shown in Help.

## Separate conversations

Choose **Chats** in the Cortex header to open the private assistant directly. **+ New** starts another topic; the chat selector returns to an earlier conversation with its questions, answers and unsent draft. The pencil renames a chat. The small × beside it deletes that chat after confirmation; the header × closes Cortex. Follow-up questions use recent completed answers from the same chat. Changing chats stops the pending question; a late answer cannot appear in the new topic.

`CortexConversations`, owned by `SpatialIntelligence`, stores text at `user://cortex/conversations.json`. There is no startup inference or automatic replay. It stores questions, answers and drafts, with no credentials, captured pictures or scene payloads. These local text files belong to the current OS account and are not encrypted. Delete removes local history; it cannot revoke data already sent to an external provider. Provider keys and permissions remain with their existing owners.

Only the latest complete pairs for the same connection, endpoint, model, goal, scene scope and image/tool settings are eligible for request history. A change starts a new context boundary. The request includes at most six pairs within a text budget (2,000 characters for bundled Qwen; 12,000 for other connections), keeping inference context bounded while the full transcript remains available locally. Interrupted, failed and cancelled turns are never sent as completed answers. Current scene context is captured afresh for each question; older pictures are never resent from chat history.

The history scrolls separately, keeping the question field and Ask button visible. All chat controls and confirmation dialogs are authored in the existing `.tscn`; the panel binds them to the conversation owner. Local chat management is available to the OS user; assistant transmission and scene actions retain `AIAccessPolicy` checks.

**Assistant & sharing** is a collapsible section inside Chat. Its closed header shows the current assistant and sharing state. Expand it to choose the connection, inspect a captured picture or change existing sharing/command permissions. Collapsing it never changes permission. A request denied by transmission consent opens the section to show the controls you need. Empty image previews consume no blank picture space. The header and question controls remain fixed while the middle content scrolls, and the panel fits the logical viewport when resizing or restoring a saved position. The shared 33% HUD size reduction and transparency remain unchanged.

## Add models or start fresh

The Import panel offers **Clear scene before importing**, initially unchecked. Leave it off to add PLY/GSRES models or a saved `.pxrscene` to the current composition. Check it to replace the current models when import begins. The checkbox returns to off after an accepted import. Cancelling the file picker does not clear anything; an invalid model header or a model that exceeds the atlas budget is rejected before replacement.

Object placement and environment entry keep their existing behavior. Replacement clears the old models before new object placement; cancelling that placement does not restore the replaced scene, so save it first if needed. Saved-scene replacement retains its existing verified checkpoint/rollback behavior. Adding a saved scene preserves the current models, camera, sky and image settings, with exact imported transforms and unique model identities; a failed added load removes only its new models. An empty viewer restores the saved scene's view. Scenes authored with a different global render orientation/scale require explicit replacement rather than an inaccurate merge. **Open scene** in Scene navigator and the established programmatic `import_path` behavior remain available.

## Use the next application run

Open the **Assist/Cortex** control on the main rig. Its three workspaces are:

- **Ask:** choose a saved connection, grant transmission to that destination and ask about the scene. Cloud and loopback consent are separate. Sending an image and allowing camera/selection commands are separate choices.
- **Select:** capture a clean view, add prompts, segment locally and inspect masks. A mask may select an existing visible model. No camera/model transform is changed by the probe, and scene changes invalidate selection from an old capture.
- **Setup:** Connections, Vision, Privacy and Diagnostics edit the existing service owners. Apply validates a copy before committing. Diagnostics distinguish model discovery, text inference, vision inference and tool schema tests; a tool diagnostic never executes scene commands.

For local language inference, go to **Setup → Connections → Start bundled Qwen**. It verifies the model/runtime and starts an owned CPU process at `127.0.0.1:18081`. Enable local endpoint analysis in Ask. This Qwen3 1.7B Q8 bundle is text-only by default, has a 2,048-token context, uses four CPU threads and disables GPU offload. Stop releases that process and its model. Ollama and compatible profiles can use another installed local model, including Mistral or Qwen variants; they do not download those additional models automatically.

For local segmentation, choose an engine under **Setup → Vision**, then apply:

- **MobileSAM:** left click adds foreground; right click or Shift-click adds background. Segment returns a mask at capture dimensions.
- **SAM3:** enter a concept such as `motorcycle` or `person`; optionally drag a box to constrain it. This supplied ONNX export has a different image/language/decoder contract, implemented separately from MobileSAM. Unsupported point prompting is disabled for this engine.

The preview and optional full-view canvas retain the same frozen capture and coordinate mapping. Capture is downscaled by the existing clean-capture owner to at most 1,280 pixels on its longest edge. Native inference and CPU mask preparation run on one private worker. Prompt edits reuse cached embeddings for the same capture. Switching engines drops the previous sessions first. Cancel discards stale results; an executing native call may finish privately. Release frees idle sessions. SAM3 CPU inference is heavier than MobileSAM: the real 1908×960 review fixture took approximately 42–67 seconds under the observed workstation load; this is not a latency promise for other hardware.

## Ownership and permissions

`CortexSettings` owns a versioned, validated non-secret document at `user://cortex/settings.json`. `CortexProviders` owns protocol defaults and allowed endpoint rules. `CortexCredentials` owns credential references and session values; a native Windows bridge owns OS credential storage. Secrets never enter the settings document, portable tree, scene, diagnostics or Git.

Credentials can be session-only, environment references or Windows Credential Manager entries. They are bound to a connection identity and endpoint. Changing destinations cannot reuse a stored session/vault key. Official provider origins are fixed; custom remote endpoints require HTTPS. The previous shared environment override is retained only for the initially selected legacy profile.

`AIAccessPolicy` remains the command authority. New sessions deny transmission and scene commands. Analysts cannot advertise or execute commands by merely enabling a model capability. A standalone OS owner may grant local operator capability explicitly; a managed policy can deny configuration and self-promotion. This is a desktop capability policy, not multi-user authentication. Provider/model capabilities are declarations until their individual tests pass.

The previously exposed API key still requires provider-account revocation. Clearing a local field, removing a vault entry or adding this UI does not revoke it.

## Portability and performance

See [the resource tree instructions](../resources/cortex/README.md). Copy the whole folder, including ignored weights/runtimes, or use the source-free package built with `--include-cortex`. Large models are intentionally absent from Git. Credentials and per-user preferences remain machine/account data.

`CortexAssets` resolves the catalog relative to the project or executable. Native sessions use verified absolute paths internally. SAM3 external weights remain beside their graphs. Signed Microsoft C++ redistributable dependencies travel with ONNX Runtime and llama.cpp; the native bridge uses safe local dependency loading without mutating PATH. Windows x86_64 is the qualified contract. No second physical computer, macOS, Linux, ARM, XR device or authenticated cloud-provider account was qualified by these local checks.

Opening Cortex starts no segmentation sessions or model runner. Its service nodes stop processing while idle, and the worker sleeps. GS loading, caching, conversion, sorting, quality, colors, shadows and transform math retain their existing owners. The viewer/UI additions are the read-only GPU picking adapter, owned panel teardown and explicit import-mode/composition-add workflow. Active CPU inference still competes for system CPU/RAM; release it when maximum loading throughput is needed.

## Qualification and remaining audit boundaries

The original machine-readable evidence is [cortex-qualification.json](audit/cortex-qualification.json). The import-mode and separate-chat release is qualified in [cortex-chats-qualification.json](audit/cortex-chats-qualification.json), including rendered UI, conversation isolation, real Qwen follow-ups and the full Bali/Suzuki population. Every original P.X.Y status remains in [the generated audit report](audit/REMEDIATION_STATUS.md), owned by its JSON source. Local inference and setup do not close external key revocation, authenticated vendor qualification, XR/custom rendering, signing/hardware or historical provenance gaps.

The subsequent overflow correction and collapsible sections are qualified in [cortex-layout-qualification.json](audit/cortex-layout-qualification.json). It records the failing connected-Help reproduction, corrected logical-viewport checks, all preset/tab states, resize/reopen and pointer interaction, preserved chat/permission behavior, GPU cleanup checks and the source-free optimized app. The qualified app is `build/cortex-layout-final/GSViewer.exe`; older qualified builds remain intact. Restart the running Godot game to instantiate the updated authored scene.
