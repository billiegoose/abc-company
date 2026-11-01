# A.P.P.L.E.P.I.E. / ANANA Camera Bridge — implementation brief

## Purpose

Enable the ANANA coding agent to see the **physical** lab: a webcam aimed at the Digilent Basys 3 board and a second webcam aimed at the VGA monitor. This complements software simulation and must not be confused with proof of hardware behavior until actual photographs are captured.

## Decisions carried over from the Camera Bridge discussion

1. **Separate security identity:** Ship a native Swift/SwiftUI macOS `.app` with AVFoundation capture, `NSCameraUsageDescription`, a stable bundle ID and a documented signing strategy. The user can review/revoke its Camera access in System Settings. Do not make Terminal or the PGC Python watcher the camera owner.
2. **Two logical instruments:** Enumerate cameras, preview their video locally, let the user assign persistent AVFoundation device `uniqueID` values to `board` and `monitor`, and select an available still-image resolution. Handle USB reconnection and missing devices gracefully.
3. **Local transport:** Expose a minimal Unix-domain-socket request/response protocol to a local PGC client. The request selects a logical camera; the app checks authorization, captures a still image, and returns an image file reference plus metadata or a structured error. Use restrictive socket permissions and validate all inputs.
4. **Two permission layers:** macOS TCC Camera permission is necessary but not sufficient. Inside A.P.P.L.E.P.I.E., maintain a per-camera automation allowlist, a visible capture indicator, and a clearly labeled, bounded unattended testing authorization if implemented. Deny by default.
5. **Image handoff:** PGC already attaches PNG/JPEG/GIF/WebP images to tool-result user turns with `attach_image {path}`; the new `camera` call should similarly deliver real pixels as an attachment alongside JSON metadata, never base64 image bytes embedded in JSON.
6. **Local-first:** No cloud upload, web server, background recording, or video stream. The only intended external transmission is the user's existing PGC-to-ChatGPT image attachment for an explicitly authorized still capture.

## Suggested milestones

- **M1 — Native app shell:** Swift package/Xcode project, stable `.app` identity, Camera privacy declaration, repeatable local build and launch instructions, basic SwiftUI status interface.
- **M2 — Camera management:** AVFoundation discovery, previews, persistent `board`/`monitor` mappings, selectable resolution, manual JPEG capture, visible activity indication and useful error states.
- **M3 — Secure local bridge:** versioned Unix-socket protocol, camera allowlist, optional time-bounded unattended mode, request limits, safe image output lifecycle, and tests using mocked capture devices.
- **M4 — PGC integration:** `camera {camera}` web orchestration tool, attachment to the same result turn, recovery/retry semantics, tests of permission failure and multi-image requests, documentation.
- **M5 — Physical qualification:** With the user's camera approval and both webcams attached, show actual board/monitor photos and validate device reconnection. Do not modify or program the FPGA during camera qualification.

## Illustrative future PGC request

```json
{"session":"<project-routing-id>","id":"inspect-board","tool":"camera","camera":"board"}
```

The routing ID is an illustrative placeholder; use the actual PGC session ID when making executable requests. An example successful result could include `camera`, `filename`, `captured_at`, dimensions, `sha256`, and `ok`, while delivering the JPEG as a binary attachment on the same ChatGPT turn.

## Operational boundaries

A.P.P.L.E.P.I.E. observes instruments; it does not operate or program them. Avoid changing the parent repository's FPGA entry points and compiler/toolchain pins. The work is a new application, not an import of an existing FPGA project. Any unavoidable parent-level integration should be independently tested and documented.
