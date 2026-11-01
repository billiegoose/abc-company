# A.P.P.L.E.P.I.E.

**ANANA Permissions Protected Lab Equipment Proxy for Internet Entities**

*Anana Banana Computing Company — Experimental Systems Division*

The laboratory is pleased to announce **A.P.P.L.E.P.I.E.**, an unusually scrupulous machine observer. Its present remit is to inspect the Digilent Basys 3 experimental computing apparatus (`board`) and the associated VGA monitor (`monitor`) using ordinary webcams. While the acronym is an administrative triumph, the photographic evidence is quite real.

A.P.P.L.E.P.I.E. is a native, standalone macOS application. The company assures its operators that no instrument will be reprogrammed in the course of observation.

## Commissioning

A.P.P.L.E.P.I.E. requires macOS 14 or later and Xcode with Swift 6. Build and test from `apps/a-liar/`:

```sh
swift test
bash scripts/build-app.sh release
open build/APPLEPIE.app
```

The resulting `.app` owns its macOS Camera permission via bundle ID `com.ananabanana.APPLEPIE` and `NSCameraUsageDescription`. Camera permission is requested only when the operator presses **Grant macOS Camera Access**. Merely launching A.P.P.L.E.P.I.E. or connecting a local socket does not open a camera.

For stable Camera authorization across rebuilds, sign with the same Apple Development or Developer ID certificate and launch from a consistent app path:

```sh
APPLEPIE_SIGN_IDENTITY="Apple Development: Your Name (TEAMID)" bash scripts/build-app.sh release
```

The default ad-hoc signature is for iteration only; macOS may treat a rebuilt ad-hoc-signed app as a different Camera-permission identity. The new `com.ananabanana.APPLEPIE` identity requires a fresh macOS Camera grant after replacing the old app.

On first launch, A.P.P.L.E.P.I.E. copies any existing camera mappings and capture-history log from `~/Library/Application Support/A-LIAR/` into its new private `~/Library/Application Support/APPLEPIE/` directory, without overwriting newer settings. The old directory and any old JPEGs remain in place for recovery; the prior unattended session grant is deliberately not transferred.

1. Open the app and grant Camera permission through macOS.
2. Assign physical webcams to `board` and `monitor`; assignments persist by AVFoundation `uniqueID`.
3. Pick a preview/JPEG resolution, start a local preview, and use **Capture JPEG** to save one frame from that same video stream. An already-running preview stays running during capture.
4. To allow PGC still capture, enable an individual camera's automation switch. Make a PGC `camera` request so its routing session appears in the app, select that session, then grant it access for **5 minutes, 15 minutes, 1 hour, 3 hours, or 6 hours**. Only that session receives the grant; restarting the app or revoking resets it.
5. PGC's `camera {camera}` tool requests a fresh still via the local socket and attaches the JPEG as a normal ChatGPT image, only when the app grants it. Every successful photograph also appears in the persistent **Capture History** log, whether taken manually or by PGC.

No background recording, remote server, cloud video stream, or FPGA programming is included.

For protocol details, safety rules, limitations, and physical qualification steps, see [engineering operation notes](docs/operation.md). The [implementation brief](docs/implementation-brief.md) remains the original specification.
