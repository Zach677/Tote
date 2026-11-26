# Tote Architecture and Decisions

Tote is a local-only iOS 26 UIKit app that unifies campus parcel pickup codes, tracking numbers, and locker actions across multiple channels in one place.

## Scope and Non-Goals

- **In scope**: Unified pending-parcel dashboard grouped by pickup point; fast copy and mark-picked actions; clipboard and Share Extension ingestion for family-shared codes and tracking numbers; iOS Shortcuts (App Intents) SMS ingestion; offline Vision OCR import for screenshots; embedded official Yixiaoji H5 tab; fast launch into Duoduo Station pickup and identity barcode pages; optional Phase 2 JD H5 sync; Phase 3 widgets and Control Center launch button.
- **Out of scope**: Cloud backend or third-party paid tracking APIs; reverse-engineering or bypassing private anti-bot signatures (such as Pinduoduo `anti_content`); bundling third-party native app launchers that the user does not install (such as standalone Cainiao or SF Express apps).

## Settled Decisions

### D1. Native UIKit Local-First Architecture
- Built on `Modern.UIKit` (iOS 26, Swift 6, programmatic UIKit, `MainActor` default isolation).
- All parcel parsing, deduplication, station classification, and state transitions live in `Packages/Core` (UI-free, tested with `mise test-core`).
- All parcel data and web sessions remain local on the user's iPhone.

### D2. Duoduo Station (Pinduoduo) Integration
- **Chosen**: Configurable deep link (`pinduoduo://com.xunmeng.pinduoduo/mdkd/package`) for 1-tap access to pending parcels, shelf photos, waybill addition, and the identity barcode tab; combined with SMS automation (Phase 2) and offline Apple Vision OCR batch screenshot import (Phase 2).
- **Rejected**: Embedded `WKWebView` login to `mobile.yangkeduo.com/mdkd/package`. Real-device verification showed that standalone browser login redirects back to the login screen within 1 second, omits the identity barcode tab, and signs out the native Pinduoduo iOS app.
- **Rejected**: Reverse-engineering private signed Pinduoduo endpoints. Even with list endpoints, parcels with mismatched phone numbers (privacy numbers or other SIMs) do not appear by phone lookup without submitting the tracking number.

### D3. Yixiaoji Locker Integration
- **Chosen**: Embed the official standalone web portal (`https://ai.iepple.com`) inside a dedicated `WKWebView` tab with a persistent `WKWebsiteDataStore`.
- **Evidence**: Real-device testing confirmed standalone username/password login (independent of WeChat), no mini-program ads, cross-locker parcel history, waybill addition, locker unlock, and gate unlock.
- **Dashboard linkage**: Tapping a Yixiaoji parcel on the dashboard copies its pickup code and switches to the Yixiaoji tab.

### D4. Cainiao, SF Express, JD, and Family-Ordered Parcels
- The user does not install standalone Cainiao or SF Express apps. Do not clutter the primary action bar with `cainiao://` or `sfexpress://` buttons.
- **Phase 1**: Clipboard auto-detection and quick entry handle family-forwarded pickup codes and tracking numbers immediately.
- **Phase 2**: iOS Shortcuts App Intents ingest pickup SMS messages automatically (covering Cainiao, SF Express, JD, and SMS-enabled stations/lockers). Add optional JD mobile H5 (`https://trade.m.jd.com/order/orderlist_jdm.shtml`) `WKWebView` sync and optional SF web lookup as decoupled adapters that merge into `Packages/Core` by tracking number or pickup code.

### D5. Fast Access to Duoduo Identity Barcode
- Keep the Duoduo deep link configurable in settings so a deeper barcode-tab route can be substituted later without an app rebuild.
- Phase 1 exposes a top primary action on the dashboard. Phase 3 adds an iOS Control Center `ControlWidget` and Lock Screen / Home Screen widgets to launch it directly without browsing the Home Screen.

### D6. Privacy and Repository Hygiene
- Never commit real phone numbers, real tracking numbers, real pickup codes, real campus/building names, real screenshots, session cookies, or personal Apple signing team IDs.
- All tests and previews must use synthetic fixtures (for example `12-3-0000`, `YT0000000000000`, `Sample Locker A1`).
- Keep personal signing settings (`DEVELOPMENT_TEAM`) in untracked `Configuration/Developer.xcconfig`.

## Phased Delivery Plan

Each phase must ship a usable, verified app on its own.

### Phase 1: Core Daily-Driver App
- Replace the `App/Interface/Root/` and `AppTests/Interface/Root/` template placeholder with the real two-tab UIKit shell:
  - **Dashboard Tab**: Diffable list grouped by pickup station (`Duoduo`, `Yixiaoji`, `Cainiao`, `SF Express`, `JD`, `Other`); large pickup code typography; tap to copy code; swipe to mark picked up / archive; quick-add bar with clipboard detection for pickup codes and pending tracking numbers; top quick action for Duoduo (`pinduoduo://com.xunmeng.pinduoduo/mdkd/package`) with copy-then-open support for pending tracking numbers.
  - **Yixiaoji Tab**: Embedded persistent `WKWebView` for `https://ai.iepple.com` with reload/home/back controls and code-copy handoff from the dashboard.
- **`Packages/Core`**: `Parcel` model, `PickupChannel` enum, local persistence store, deterministic `PickupParser` (SMS text, family chat text, carrier waybill detection), deduplication engine, and comprehensive Swift Testing coverage.
- **Verification**: `mise check` passes cleanly (`format-lint`, `validate-xcstrings`, `test-core`, `test-app`).

### Phase 2: Automated Ingestion
- App Intents endpoint for iOS Shortcuts "Message" personal automations (SMS -> `PickupParser` -> shared store).
- Offline Apple Vision OCR (`VNRecognizeTextRequest`) to batch-import parcels from screenshots (such as Duoduo `mdkd/package` screenshots).
- Optional JD mobile H5 `WKWebView` adapter (`trade.m.jd.com`) and optional Yixiaoji pending-list DOM sync into the unified dashboard.

### Phase 3: System Surfaces
- `WidgetKit` Home Screen and Lock Screen widgets showing remaining parcel count and top pickup codes.
- iOS Control Center `ControlWidget` for 1-tap Duoduo identity barcode launch.
- Share Extension to send family messages or screenshots from WeChat directly into Tote.

## Open Items and Unverified Assumptions

| Item | Why Deferred | Verification Needed |
| --- | --- | --- |
| Impact of disabling Taobao privacy numbers | User just disabled privacy numbers; requires new incoming deliveries to observe | Confirm whether new non-PDD deliveries appear automatically in PDD and Yixiaoji |
| Physical locker unlock on `ai.iepple.com` | Must be tested while physically standing at a locker | Verify "Open Locker" with pickup code opens the physical door |
| `ai.iepple.com` session lifetime in `WKWebView` | Needs multi-day real-device observation | Observe how often re-login is required after Phase 1 installs on iPhone |
| JD H5 (`trade.m.jd.com`) vs JD iOS app session coexistence | Deferred until Phase 2 JD adapter work | Test on device whether logging into `trade.m.jd.com` affects the native JD app |
| Deeper PDD URL scheme directly opening the identity barcode tab | Public research only confirmed `mdkd/package` | Test any newly discovered route via the configurable URL setting |
