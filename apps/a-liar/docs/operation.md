# A.P.P.L.E.P.I.E. — engineering operation notes

## Build and application identity

- macOS 14+; Xcode 26.5 and Swift 6.3 verified during development.
- `swift test` tests pure configuration, camera selection, authorization, capture files, and the socket against mock capture handlers. It never opens a webcam.
- `bash scripts/build-app.sh [debug|release]` creates `build/APPLEPIE.app`, copies the privacy-bearing `Info.plist`, signs with `APPLEPIE_SIGN_IDENTITY` (default `-` for ad hoc), and verifies the signature. Run it with `bash`; the script need not be executable.
- Bundle identifier is `com.ananabanana.APPLEPIE`. For a durable TCC identity, always use the same signing certificate and a consistent app location such as `/Applications/APPLEPIE.app`. The default ad-hoc signature is not a durable identity across rebuilds. Check with `codesign -dv --verbose=4 build/APPLEPIE.app`.
- The app is unsandboxed. No Terminal/Python/PGC process requests Camera permission; only this app uses AVFoundation.
- This rename changes the bundle ID to `com.ananabanana.APPLEPIE`, so macOS Camera permission must be granted again. At first launch, a one-time migration copies only `settings.json` and `capture-history.jsonl` from the former `A-LIAR` Application Support directory when the new files do not already exist. Original files (including prior JPEGs) stay untouched for recovery; previous unattended access is never migrated. Old JPEG paths recorded in the copied history remain readable from the original directory while those files exist.

## Explicit privacy boundaries

1. App launch may list camera *names* but does not start sessions or ask for Camera permission.
2. A press on **Grant macOS Camera Access** invokes the ordinary macOS TCC prompt. A denied prompt must be changed in System Settings → Privacy & Security → Camera.
3. A press on **Start preview** or **Capture JPEG** is the app-level manual permission to activate that selected camera. Live previews are confined to the native window.
4. Automation starts denied. A persistent per-role `automationAllowed` switch is **not** sufficient. A PGC `camera` request identifies the routing session, but does not authorize capture. The operator then selects that session and explicitly grants it a 5-minute to 6-hour window. Only that exact routing session is allowed; a different session is denied. One session at a time may hold a grant. The grant lives in memory, expires automatically, and is never loaded from disk. Revoking stops an ongoing automated capture. Reassigning a physical camera revokes its automation allowlist entry. This is an app-level routing scope within a same-user trust boundary, not cryptographic protection against malicious same-UID processes.
5. Local agent requests and capture activity appear in the app status line; a red **CAPTURING** banner appears during still capture. Each successful manual or PGC photo is appended to a private `capture-history.jsonl` log, visible in the app with timestamp, role, source, dimensions, size, optional PGC session, and a Reveal action while the JPEG exists. History survives app restarts even after JPEG expiry. The app now JPEG-encodes exactly one on-demand frame from the same AVFoundation video stream used for the preview, at its selected preview resolution. It does not configure a separate AVCapturePhotoOutput. An already-running preview is reused rather than restarted; a newly started stream gets a brief auto-exposure warm-up before its frame is captured. Idle frames are discarded rather than recorded.
6. A.P.P.L.E.P.I.E. creates no TCP or HTTP listener and never streams video or uploads images. PGC may send one explicitly authorized JPEG as a ChatGPT image attachment using the normal conversation channel; that is the only intended external image transmission.

## Local Unix socket (protocol version 2)

Socket: `~/Library/Application Support/APPLEPIE/capture.sock` (0600) in a private (0700) app data directory. Its `capture.lock` file prevents two running app instances from replacing the same listener. Only a connecting process with the same Unix user ID is served. Each connection handles exactly one request and then closes. Client request must end in a newline, be no larger than 4096 bytes, and arrive within five seconds. Capture is independently bounded by a 20-second timeout.

Request:

```json
{"version":2,"command":"capture","camera":"board","session":"83a276118d7867c4","request_id":"optional-safe-id"}
```

Only `board` and `monitor` are accepted. The required `session` field is the validated PGC routing identifier, limited to 128 ASCII characters. It must match the session explicitly granted by the operator. No caller-supplied output path, arbitrary device ID, file management command, or network address is allowed. Unknown request keys are rejected. On success, the app returns one newline-terminated JSON object containing `ok`, `version`, `camera`, `filename`, `captured_at`, `width`, `height`, `byte_count`, and `sha256`. On failure, it returns `ok:false`, `code`, and `error`. JPEG bytes are **not** placed inside JSON.

Captures are saved under `~/Library/Application Support/APPLEPIE/captures/`, directory mode 0700, generated `board-UUID.jpg` or `monitor-UUID.jpg` filenames, file mode 0600. A 16 MiB maximum JPEG size is enforced. Images older than ten minutes are cleared on the next successful capture, but their metadata remains permanently in the private `capture-history.jsonl` history unless explicitly removed outside the app. The PGC client checks the returned path, owner, size, JPEG signature, and SHA-256 and then places the verified bytes into the existing image attachment pipeline. Responses already staged for browser delivery are kept in memory across delivery retries, so capture is not repeated.

PGC syntax once the PGC source integration is loaded/restarted:

```json
{"session":"<current-PGC-routing-id>","id":"inspect-board","tool":"camera","camera":"board"}
```

If the app is closed, Camera permission is denied, the chosen webcam disconnects, the camera isn't allowlisted, or the unattended window expires, the request fails without attaching an image. Batch calls can request both roles; PGC's 40 MiB total image limit still applies. The `chatgpt-web` backend supports attachments; the `terminal-browser` backend returns an unsupported-tool error.

## Physical qualification checklist (requires Billie)

- [ ] With the app launched from its final signed location, approve Camera access through macOS and confirm it appears under Camera privacy settings.
- [ ] With both webcams connected, verify they appear separately, assign `board` and `monitor`, relaunch, and verify mappings persist.
- [ ] Start each preview and confirm the physical instrument in each; manually capture both, inspect actual JPEG dimensions and content, and check the red capture indicator.
- [ ] Unplug/replug one USB webcam: expect a disconnected state, unchanged mapping, and restoration on reappearance without accidental remapping.
- [ ] With automation locked, send a `camera` request: expect `unattended_access_inactive` or `camera_not_allowed`, no image. Allow one role, select the requesting PGC session, and grant five minutes; expect one real JPEG attachment and a persistent history entry. Confirm a different routing session or disallowed camera is denied, and the six-hour option never exceeds six hours.
- [ ] Revoke during a capture and verify it is cancelled. Confirm expiry and app relaunch re-lock automation.
- [ ] Confirm no Camera permission is requested by Terminal or PGC; no hardware bitstream or firmware is modified.

## Known software-vs-physical boundary

The Swift app and the mock socket/PGC integration compile and have automated tests. The operator's two physical webcams and TCC approval are needed to prove on-device previews, actual supported resolution selection, macOS AVFoundation still-photo delivery, and real ChatGPT image upload. A green software test is not a claim that physical capture has been qualified.
