# A.P.P.L.E.P.I.E. implementation guidance

Read this file and `docs/implementation-brief.md` before implementation. Also obey the parent ANANA workspace `AGENTS.md` and active migration procedure. Keep work scoped to `apps/a-liar/` unless an integration change outside this directory is necessary and can be reviewed separately. Do not disturb the ongoing fpgatool migration or another agent's work.

## Mission

Build a small **native, standalone macOS `.app`** named **A.P.P.L.E.P.I.E.** (ANANA Permissions Protected Lab Equipment Proxy for Internet Entities). Use Swift/SwiftUI and AVFoundation, with a stable bundle identifier and `NSCameraUsageDescription` so macOS Camera permission belongs to this app, not Terminal, Python, or Poor Girl's Codex. Document local building, launch, signing, and Camera authorization. Never bypass macOS privacy controls.

Discover physical capture devices and persist user-chosen device `uniqueID` mappings to logical camera names `board` (Basys 3 FPGA) and `monitor` (its VGA display). Provide previews and a visible, unambiguous indication whenever capture is requested or underway. Capture still frames to local JPEG files at a selectable supported resolution, with errors for disconnected or unauthorized devices.

Design a **local Unix-domain-socket** interface so a PGC agent can request a photo by logical camera name without acquiring Camera permission itself. Require app-enforced camera allowlisting and a clear authorization model for automation; make unattended access opt-in and time-limited if offered. Keep the socket local, validate requests, bound capture/file sizes and timeouts, avoid path traversal, and fail closed. Do not expose a remote network service or stream video to a cloud service.

The PGC source checkout already supports `attach_image {path}` with image bytes attached alongside JSON tool results. Integrate a `camera {camera}` orchestration call only after the standalone app and local capture interface are working; the camera result should include status/metadata and a normal ChatGPT image attachment. The bridge must never require PGC itself to open AVFoundation capture devices.

Build iteratively with automated tests for configuration, protocol, permission/error handling and camera selection. Physical tests require connected devices and the user's ordinary macOS permission approval. Do not load, flash, or program FPGA hardware, or alter its files, without an explicit separate request. Prefer deterministic tests that run without physical equipment. Document remaining manual hardware checks.

Work toward a working application, rather than stopping after a design document. Make progress visible in the new PGC conversation and report build/test results and any permission blockers.
