# Tote Architecture and Decisions

Tote is a local-only iOS 26 UIKit app that unifies campus parcel pickup codes, tracking numbers, and locker actions across multiple channels in one place.

## Scope and Non-Goals

- **In scope**: Unified pending-parcel dashboard grouped by pickup point; fast copy and mark-picked actions; clipboard ingestion for family-shared codes and tracking numbers; unified App Intents ingestion for iOS Shortcuts (screenshot text extraction, Share Sheet shortcuts, SMS automations, and clipboard actions); native Yixiaoji locker sync and unlock with Safari H5 fallback; fast launch into Duoduo Station pickup and identity barcode pages; Phase 3 widgets and Control Center launch button.
- **Out of scope**: Cloud backend or third-party paid tracking APIs; reverse-engineering or bypassing private anti-bot signatures (such as Pinduoduo `anti_content`); bundling third-party native app launchers that the user does not install (such as standalone Cainiao or SF Express apps).

## Settled Decisions

### D1. Native UIKit Local-First Architecture
- Built on `Modern.UIKit` (iOS 26, Swift 6, programmatic UIKit, `MainActor` default isolation).
- All parcel parsing, deduplication, station classification, and state transitions live in `Packages/Core` (UI-free, tested with `mise test-core`).
- All parcel data and web sessions remain local on the user's iPhone.

### D2. Duoduo Station (Pinduoduo) Integration
- **Chosen**: Configurable deep link (`pinduoduo://com.xunmeng.pinduoduo/mdkd/package`) for 1-tap access to pending parcels, shelf photos, waybill addition, and the identity barcode tab; combined with unified App Intent ingestion (Phase 2) so screenshots or copied codes from Pinduoduo and Taobao enter Tote without switching apps.
- **Rejected**: Embedded `WKWebView` login to `mobile.yangkeduo.com/mdkd/package`. Real-device verification showed that standalone browser login redirects back to the login screen within 1 second, omits the identity barcode tab, and signs out the native Pinduoduo iOS app.
- **Rejected**: Reverse-engineering private signed Pinduoduo endpoints (`anti_content`). Even with list endpoints, multi-channel stations split inbound records across Pinduoduo and Taobao/Cainiao, and privacy-number or other-SIM deliveries do not appear by phone lookup without submitting the tracking number.

### D3. Yixiaoji Locker Integration
- **Chosen (Native 1B)**: Communicate directly with the undocumented endpoints used by the official `https://ai.iepple.com` H5 portal (`h5_login`, `userinfo`, `search`, `getLocalizationList`, `tackLockOrder`, `checkOrder`) using `URLSession`, storing the user's session token locally in iOS Keychain (`KeychainYixiaojiSessionStore`). No embedded `WKWebView` tab.
- **Fail-Closed Unlock & Sync Constraints**:
  - Never send `tackLockOrder` without an explicit locker target (`cabinetMAC` or `siteID`) or while locker metadata is still loading.
  - Never treat an empty `order_sn` or failed `checkOrder` as a confirmed open; surface an unconfirmed warning so the user checks the door before retrying.
  - Reconcile picked-up state on `source == .synced` locker parcels only when the remote pending fetch completed without pagination truncation; never auto-complete pasted or manual parcels.
  - Keep **Open Yixiaoji in Safari** (`https://ai.iepple.com/h5/#/`) as the fallback whenever the undocumented protocol changes, expires, or requires WeChat overdue payment.
- **Rejected**: Embedded `WKWebView` tab. Real-device dogfooding showed the WebView was redundant and opened on the account's previously bound station rather than the parcel's actual cabinet.

### D4. Cainiao, SF Express, JD, and Family-Ordered Parcels
- The user does not install standalone Cainiao or SF Express apps. Do not clutter the primary action bar with `cainiao://` or `sfexpress://` buttons.
- **Phase 1**: Explicit paste via native `UIPasteControl` inside the Quick Add sheet (plus manual entry fallback from both empty and unparsed states) handles family-forwarded pickup codes and tracking numbers immediately without triggering iOS automatic pasteboard permission banners.
- **Phase 2**: A single `AddParcelsFromText` App Intent in the main app target serves as the unified ingestion path for iOS Shortcuts:
  - Screenshot / Share Sheet capture via Shortcuts' built-in **Extract Text from Image** action (covers Taobao app notifications, Pinduoduo pickup screens, and WeChat images without an early Share Extension target or App Group migration).
  - SMS personal automations as an additional trigger feeding the same intent (real-device evidence showed Taobao deliveries to Duoduo Station often notify via Taobao app push rather than SMS, so SMS alone is insufficient).
  - One-tap clipboard ingestion via Action Button or Back Tap.
  - Custom Apple Vision OCR (`VNRecognizeTextRequest`) is deferred unless Shortcuts' built-in text extraction proves inaccurate on real screenshots. Optional JD H5 / SF web sync remains deferred.

### D5. Fast Access to Duoduo Identity Barcode
- Keep the Duoduo deep link configurable in settings so a deeper barcode-tab route can be substituted later without an app rebuild.
- Validate custom Duoduo links in Settings as non-empty `<scheme>://<host-or-path>` URLs (trimmed, rejecting scheme-less text or empty `scheme://` shells) so the validation rule matches the user-facing error guidance.
- Phase 1 exposes a top primary action row on the Pending list (always visible, including empty state) and copy-then-open directly on each tracking-only parcel row. Phase 3 adds an iOS Control Center `ControlWidget` and Lock Screen / Home Screen widgets to launch it directly without browsing the Home Screen.

### D6. Privacy and Repository Hygiene
- Never commit real phone numbers, real tracking numbers, real pickup codes, real campus/building names, real screenshots, session cookies, or personal Apple signing team IDs.
- All tests and previews must use synthetic fixtures (for example `12-3-0000`, `YT0000000000000`, `Sample Locker A1`).
- Keep personal signing settings (`DEVELOPMENT_TEAM`) in untracked `Configuration/Developer.xcconfig`.
- Never log full Yixiaoji request URLs because the undocumented H5 search endpoints require `token` in URL query parameters.

### D7. Phase 1 UI Shell, Lifecycle, and Local Persistence
- **Single-Navigation Shell**: `RootViewController` is a `UINavigationController` hosting `DashboardViewController` directly (no bottom tab bar now that Yixiaoji uses native 1B integration).
- **Visual Identity**: Warm "kraft" amber `AccentColor` (`#9C5700` Light / `#F5A83B` Dark); system-colored SF Symbols per `PickupChannel` (no third-party brand logos); large bold tabular pickup codes and SF Mono tracking numbers.
- **List Grouping**: Pending view shows (1) the Duoduo action row, (2) non-empty `PickupChannel` sections in default physical-group order (`station`, `locker`, `jd`, `sfExpress`, `other` — **驿站 / 快递柜 / 京东 / 顺丰 / 其他**, merging campus station brands such as Duoduo Station and Cainiao Station under `station`, and smart lockers such as Yixiaoji under `locker`) with station names as secondary text, and (3) a dedicated **Waiting for Pickup Code** section at the bottom for tracking-only parcels.
- **Bare-Code Format Heuristics**: Explicit channel keywords always win. When no explicit channel is present, physical pickup-point code shapes take precedence over carrier tracking prefixes: 3-part numeric shelf codes (`^\d{1,3}-\d{1,2}-\d{3,5}$`) → `station`; 8-digit numeric codes (`^\d{8}$`) → `locker`. Otherwise carrier tracking prefixes (`SF` / `JD`) apply, followed by courier code shapes: 2-part letter+digits-4digits (`^[A-Za-z]\d{1,2}-\d{4}$`) → `jd`; 4-digit numeric codes (`^\d{4}$`, excluding calendar years `1900...2099`) → `sfExpress`.
- **Parcel Lifecycle**: Two states (`pending` and `pickedUp`), plus permanent deletion (full swipe disabled on Delete). The **Picked Up** segment serves as history/undo (swipe to restore); picked-up parcels older than 30 days are auto-pruned locally. No separate archive state.
- **Quick Add Flow**: Presented via the navigation bar `+` button as a large sheet with `UIPasteControl`, live `PickupParser` preview rows with an inline 1-tap channel switcher menu (plus tap-to-edit detail form), duplicate detection against existing pending parcels (including an explicit duplicate alert on manual entry), and direct **Enter Manually** access from both initial and unparsed states.
- **Settings Sheet**: Presented via the navigation bar gear button with explicit leading close button (discarding unsaved edits) and trailing Done button to manage the Yixiaoji Keychain account/sync and edit/test/reset the Duoduo deep link.
- **Locker Unlock Sheet**: Tapping a Locker parcel presents `LockerUnlockViewController` to confirm or choose the cabinet (fail-closed until a cabinet is selected), copy the code, unlock natively, view the opened compartment number (or unconfirmed warning), and mark the parcel picked up in one tap.
- **Local Persistence**: `Packages/Core` stores parcels in a zero-dependency atomic JSON file at an injectable directory `URL` (keeping `mise test-core` fast on macOS and allowing Phase 3 widgets to switch directly to an App Group container URL).

### D8. Pre-Launch No Backward Compatibility
- Do not add backward-compatibility shims, legacy enum/key decoders, or storage/schema migrations while Tote is pre-launch.
- Keep models, persistence formats, and settings clean; revisit compatibility and migrations only after official public release.

## Phased Delivery Plan

Each phase must ship a usable, verified app on its own.

### Phase 1: Core Daily-Driver App
- Single-navigation UIKit app (`RootViewController` -> `DashboardViewController`):
  - **Parcels Dashboard**: Diffable list with Pending / Picked Up segment switch and pull-to-refresh Yixiaoji sync; top Duoduo quick-action row (`pinduoduo://com.xunmeng.pinduoduo/mdkd/package`); non-empty `PickupChannel` sections (`Station`, `Locker`, `JD`, `SF Express`, `Other`) with station/cabinet names in secondary text; dedicated bottom **Waiting for Pickup Code** section for tracking-only parcels (tap copies tracking number and opens Duoduo); large tabular pickup code typography; tap to copy code (or open native Locker Unlock sheet for Locker parcels); swipe to mark picked up / restore / delete; navigation bar `+` opens Quick Add sheet with `UIPasteControl`, live parser preview with 1-tap inline channel switching, tap-to-edit detail form, and manual entry from both initial and unparsed states; navigation bar gear opens Settings sheet with leading close button to manage Yixiaoji Keychain login/sync and edit/test/reset the Duoduo deep link.
  - **Native Yixiaoji Locker (1B)**: Keychain-backed `LiveYixiaojiClient` (`h5_login`, `userinfo`, `search`, `getLocalizationList`, `tackLockOrder`, `checkOrder`), fail-closed `LockerUnlockViewController` sheet, two-way sync reconciliation for non-truncated remote lists, and Safari H5 fallback.
- **`Packages/Core`**: `Parcel` model, `PickupChannel` enum, `ParcelStatus` (`pending` / `pickedUp`), atomic JSON `ParcelStore` with 30-day picked-up auto-pruning and synced-parcel reconciliation, deterministic `PickupParser` (SMS text, family chat text, bare-code format heuristics, carrier waybill detection), deduplication/merge engine, `DuoduoLinkValidator`, `YixiaojiModels` lossy response decoders, and comprehensive Swift Testing coverage.
- **Verification**: `mise check` passes cleanly (`format-lint`, `validate-xcstrings`, `test-core`, `test-app`).

### Phase 2: Unified Shortcuts Ingestion (Option E)
- `AddParcelsFromTextIntent` (`AppIntents` in main app target) + `AppShortcutsProvider` so iOS Shortcuts covers screenshot OCR (built-in **Extract Text from Image** + Share Sheet), SMS personal automations, and clipboard Action Button / Back Tap via one ingestion path.
- Automatic foreground dashboard refresh when parcels are added outside the foreground UI.
- Custom offline Apple Vision OCR (`VNRecognizeTextRequest`) only if built-in Shortcuts text extraction proves insufficient on real screenshots.

### Phase 3: System Surfaces
- Migrate `ParcelStore` directory URL to an App Group container.
- `WidgetKit` Home Screen and Lock Screen widgets showing remaining parcel count and top pickup codes.
- iOS Control Center `ControlWidget` for 1-tap Duoduo identity barcode launch.

## Open Items and Unverified Assumptions

| Item | Why Deferred | Verification Needed |
| --- | --- | --- |
| Physical locker unlock on `ai.iepple.com` | Must be tested while physically standing at a locker | Verify `tackLockOrder` + `checkOrder` opens the physical door and returns the compartment number |
| `ai.iepple.com` Keychain token lifetime | Needs multi-day real-device observation | Observe how often re-login is required and whether `userinfo` refreshes tokens |
| Shortcuts built-in "Extract Text from Image" accuracy on iOS 26 | Needs real Taobao / Pinduoduo / WeChat screenshots on device | Verify whether built-in OCR cleanly feeds `AddParcelsFromTextIntent` or if custom Vision OCR is needed |
| Deeper PDD URL scheme directly opening the identity barcode tab | Public research only confirmed `mdkd/package` | Test any newly discovered route via the configurable URL setting |
