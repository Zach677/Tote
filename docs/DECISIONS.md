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
- **Chosen (Native 1B)**: Communicate directly with the official `https://ai.iepple.com` REST endpoints (`h5_login`, `userinfo`, `search`, `getLocalizationList`, `tackLockOrder`, `checkOrder`) using `URLSession` and store the user's session token locally in iOS Keychain (`KeychainYixiaojiSessionStore`). No embedded `WKWebView` tab.
- **Sync & Unlock UX**: Pulling to refresh on the Pending list (or tapping Sync in Settings) fetches pending locker parcels with their exact cabinet name, `bind_mac`, and `express_uids`, merging them into `ParcelStore` without duplicates. Tapping a Locker parcel presents a native confirmation sheet (`LockerUnlockViewController`) that displays the pickup code, auto-matches or lets the user select the exact cabinet, unlocks on explicit tap, displays the opened compartment number (`box_code`/`dev_code`), handles overdue payment (`is_pay == 0`) with a WeChat payment notice, and keeps an **Open Yixiaoji in Safari** fallback link.
- **Rejected**: Embedded `WKWebView` tab. Real-device dogfooding showed the WebView was redundant and opened on the account's previously bound station rather than the parcel's actual cabinet; inspecting the public H5 bundle confirmed clean token-authenticated REST endpoints with zero anti-bot signing.

### D4. Cainiao, SF Express, JD, and Family-Ordered Parcels
- The user does not install standalone Cainiao or SF Express apps. Do not clutter the primary action bar with `cainiao://` or `sfexpress://` buttons.
- **Phase 1**: Explicit paste via native `UIPasteControl` inside the Quick Add sheet (plus manual entry fallback from both empty and unparsed states) handles family-forwarded pickup codes and tracking numbers immediately without triggering iOS automatic pasteboard permission banners.
- **Phase 2**: iOS Shortcuts App Intents ingest pickup SMS messages automatically (covering Cainiao, SF Express, JD, and SMS-enabled stations/lockers). Add optional JD mobile H5 (`https://trade.m.jd.com/order/orderlist_jdm.shtml`) `WKWebView` sync and optional SF web lookup as decoupled adapters that merge into `Packages/Core` by tracking number or pickup code.

### D5. Fast Access to Duoduo Identity Barcode
- Keep the Duoduo deep link configurable in settings so a deeper barcode-tab route can be substituted later without an app rebuild.
- Validate custom Duoduo links in Settings as non-empty `<scheme>://<host-or-path>` URLs (trimmed, rejecting scheme-less text or empty `scheme://` shells) so the validation rule matches the user-facing error guidance.
- Phase 1 exposes a top primary action row on the Pending list (always visible, including empty state) and copy-then-open directly on each tracking-only parcel row. Phase 3 adds an iOS Control Center `ControlWidget` and Lock Screen / Home Screen widgets to launch it directly without browsing the Home Screen.

### D6. Privacy and Repository Hygiene
- Never commit real phone numbers, real tracking numbers, real pickup codes, real campus/building names, real screenshots, session cookies, or personal Apple signing team IDs.
- All tests and previews must use synthetic fixtures (for example `12-3-0000`, `YT0000000000000`, `Sample Locker A1`).
- Keep personal signing settings (`DEVELOPMENT_TEAM`) in untracked `Configuration/Developer.xcconfig`.

### D7. Phase 1 UI Shell, Lifecycle, and Local Persistence
- **Single-Navigation Shell**: `RootViewController` is a `UINavigationController` hosting `DashboardViewController` directly (no bottom tab bar now that Yixiaoji uses native 1B integration).
- **Visual Identity**: Warm "kraft" amber `AccentColor` (`#9C5700` Light / `#F5A83B` Dark); system-colored SF Symbols per `PickupChannel` (no third-party brand logos); large bold tabular pickup codes and SF Mono tracking numbers.
- **List Grouping**: Pending view shows (1) the Duoduo action row, (2) non-empty `PickupChannel` sections in default physical-group order (`station`, `locker`, `jd`, `sfExpress`, `other` — **驿站 / 快递柜 / 京东 / 顺丰 / 其他**, merging campus station brands such as Duoduo Station and Cainiao Station under `station`, and smart lockers such as Yixiaoji under `locker`) with station names as secondary text, and (3) a dedicated **Waiting for Pickup Code** section at the bottom for tracking-only parcels.
- **Bare-Code Format Heuristics**: When a pasted snippet has no explicit channel keyword and no carrier-prefixed tracking number, `PickupParser` infers default channels from common pickup-code shapes: 3-part numeric shelf codes (`^\d{1,3}-\d{1,2}-\d{3,5}$`) → `station`; 8-digit numeric codes (`^\d{8}$`) → `locker`; 2-part letter+digits-4digits (`^[A-Za-z]\d{1,2}-\d{4}$`) → `jd`; 4-digit numeric codes (`^\d{4}$`, excluding calendar years `1900...2099`) → `sfExpress`. Explicit channel keywords and tracking prefixes always override format heuristics.
- **Parcel Lifecycle**: Two states (`pending` and `pickedUp`), plus permanent deletion (full swipe disabled on Delete). The **Picked Up** segment serves as history/undo (swipe to restore); picked-up parcels older than 30 days are auto-pruned locally. No separate archive state.
- **Quick Add Flow**: Presented via the navigation bar `+` button as a large sheet with `UIPasteControl`, live `PickupParser` preview rows with an inline 1-tap channel switcher menu (plus tap-to-edit detail form), duplicate detection against existing pending parcels (including an explicit duplicate alert on manual entry), and direct **Enter Manually** access from both initial and unparsed states.
- **Settings Sheet**: Presented via the navigation bar gear button with explicit leading close button (discarding unsaved edits) and trailing Done button to manage the Yixiaoji Keychain account/sync and edit/test/reset the Duoduo deep link.
- **Locker Unlock Sheet**: Tapping a Locker parcel presents `LockerUnlockViewController` to confirm or choose the cabinet, copy the code, unlock natively, view the opened compartment number, and mark the parcel picked up in one tap.
- **Local Persistence**: `Packages/Core` stores parcels in a zero-dependency atomic JSON file at an injectable directory `URL` (keeping `mise test-core` fast on macOS and allowing Phase 2/3 to switch directly to an App Group container URL).

### D8. Pre-Launch No Backward Compatibility
- Do not add backward-compatibility shims, legacy enum/key decoders, or storage/schema migrations while Tote is pre-launch.
- Keep models, persistence formats, and settings clean; revisit compatibility and migrations only after official public release.

## Phased Delivery Plan

Each phase must ship a usable, verified app on its own.

### Phase 1: Core Daily-Driver App
- Replace the `App/Interface/Root/` and `AppTests/Interface/Root/` template placeholder with the real single-navigation UIKit app (`RootViewController` -> `DashboardViewController`):
  - **Parcels Dashboard**: Diffable list with Pending / Picked Up segment switch and pull-to-refresh Yixiaoji sync; top Duoduo quick-action row (`pinduoduo://com.xunmeng.pinduoduo/mdkd/package`); non-empty `PickupChannel` sections (`Station`, `Locker`, `JD`, `SF Express`, `Other`) with station/cabinet names in secondary text; dedicated bottom **Waiting for Pickup Code** section for tracking-only parcels (tap copies tracking number and opens Duoduo); large tabular pickup code typography; tap to copy code (or open native Locker Unlock sheet for Locker parcels); swipe to mark picked up / restore / delete; navigation bar `+` opens Quick Add sheet with `UIPasteControl`, live parser preview with 1-tap inline channel switching, tap-to-edit detail form, and manual entry from both initial and unparsed states; navigation bar gear opens Settings sheet with leading close button to manage Yixiaoji Keychain login/sync and edit/test/reset the Duoduo deep link.
  - **Native Yixiaoji Locker (1B)**: Keychain-backed `LiveYixiaojiClient` (`h5_login`, `userinfo`, `search`, `getLocalizationList`, `tackLockOrder`, `checkOrder`), pull-to-refresh pending locker sync with exact cabinet `bind_mac`, and native `LockerUnlockViewController` sheet (auto-match or choose cabinet, explicit unlock tap, opened compartment display, overdue WeChat payment notice, and Safari H5 fallback).
- **`Packages/Core`**: `Parcel` model, `PickupChannel` enum, `ParcelStatus` (`pending` / `pickedUp`), atomic JSON `ParcelStore` with 30-day picked-up auto-pruning and synced-parcel enrichment, deterministic `PickupParser` (SMS text, family chat text, bare-code format heuristics, carrier waybill detection), deduplication/merge engine, `DuoduoLinkValidator`, `YixiaojiModels` lossy response decoders, and comprehensive Swift Testing coverage.
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
