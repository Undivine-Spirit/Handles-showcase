# handles_app

The Flutter app (Windows + Android, `docs/PROJECT_PLAN.md` section 6) - the
first real screen implementing the
[Handles Console](https://claude.ai/code/artifact/6fa0bcdc-c457-429f-8017-07857742a8bb)
visual direction as actual widgets, not a static mockup. Depends on
[`../core`](../core) for the catalog model, adapters, and category system -
this package holds UI, platform-specific storage, and OAuth plumbing.

## Status

- [x] Console screen - masthead, stat row, catalog table (sorted by
      `Settings > Priority Categories`), activity log and hardware panels.
      Backed by sample data (`lib/data/sample_catalog.dart`), not a real
      repo-backed catalog yet.
- [x] Settings screen - eBay developer app config, Walmart seller
      credentials (a simpler connect flow than eBay's - client-credentials
      grant, no browser step, validated immediately on Save), per-account
      connect/disconnect with live status, a Sourcing Engine section
      (Keepa key + default markup, ready for whenever the sourcing engine
      itself is wired up), priority-category ordering, and user-added
      custom categories with their own recommender keywords.
- [x] Add Item screen - live category suggestions from `core`'s
      `CategoryRecommender` as the title/description are typed, with the
      match explained (which keywords fired), not just asserted.
- [x] Real cross-platform secure credential storage
      (`services/secure_credential_store.dart`, backed by
      `flutter_secure_storage` - Windows DPAPI / Android Keystore) and
      settings persistence (`services/shared_prefs_settings_store.dart`).
      This is what makes "auto login" real: a seller account's OAuth
      refresh token survives an app restart, encrypted at rest.
- [x] eBay account connection flow
      (`services/ebay_loopback_auth_flow.dart`) - opens the user's own
      system browser to eBay's login page (this app never sees a
      password) and catches the OAuth redirect via a temporary local
      HTTP listener. **Not yet tested against a real eBay account** - no
      developer credentials exist yet (application pending re-review, see
      project notes) - and the redirect-URI/RuName setup this depends on
      is documented but not re-verified against eBay's current developer
      portal UI.
- [x] `flutter analyze`: no issues. `flutter test`: 18 tests passing -
      recommender wiring, priority-category sorting, settings screen's
      category management, and now `AppState`'s connect/save/disconnect
      actions directly (config validation, persistence, notifyListeners)
      rather than only exercised indirectly through widgets.
- [ ] **Not yet run natively.** Windows Developer Mode is enabled now, but
      the Windows C++ desktop toolchain (Visual Studio) and Android
      command-line tools still aren't installed. Verified instead by
      running on the Flutter web target as a preview (same widget code,
      different renderer) - see project notes for what that looked like.
- [ ] Wiring to the real catalog (`catalog/*.json` via the GitHub state
      layer) and the reconciliation engine - both exist in `core/` already,
      just not connected to this UI yet. Items added via "Add Item" only
      live in this session's memory right now.

## Running this yourself

```bash
cd app
flutter pub get
flutter analyze
flutter test
flutter run -d windows   # once Visual Studio's C++ workload is installed
flutter run -d android   # once an Android device/emulator + cmdline-tools are set up
flutter run -d web-server --web-port 8765   # quick preview without either toolchain
```
