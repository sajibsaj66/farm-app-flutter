# QA Report — Farm ERP + Animal Health & Illness Management

Environment: Windows 11, Flutter 3.47.0 (stable), Dart 3.13.0. Every command below was **actually run** in this environment, with the result shown.

## Commands executed

| Command | Result |
|---|---|
| `flutter pub get` (after adding `url_launcher`) | OK |
| `flutter analyze` | **No issues found** |
| `flutter test` | **106 tests, all passed** |
| `flutter build apk --debug` | **Built** `build/app/outputs/flutter-apk/app-debug.apk` (Gradle 157 s, includes the url_launcher plugin) |

Per test file:

| File | Tests | Result | Covers |
|---|---|---|---|
| `test/health_test.dart` | 18 | passed | The 16 required health checks: create illness (health status set, operational status and production untouched, blank temperature stays blank); update keeps id/creation time; restore after restart; correct animal link, unknown/archived animal refused, animal with cases not deletable; symptoms without diagnosis (suspected cause is not a diagnosis); consultation — suspected vs confirmed (confirmed needs vet + diagnosis), report preserved, future date refused; treatment plan → Under treatment + milk withheld; medication Given/Delayed/Missed/Discontinued/Scheduled rules, plan never auto-changed; **no duplicate stock deduction** (re-save, edit, repeat submit refused, Missed returns stock, delete restores, plan change does not alter a past dose, insufficient stock refused, locked stock movement); follow-up scheduling/overdue/progress and non-duplicated reminders; **no automatic recovery** when the end date passes; recovery only by owner/manager with notes + confirmation, blocked by ongoing treatment/scheduled follow-up, history kept, closed case refuses entries, reopen keeps previous outcome; dashboard search & filters, record search, all health reports CSV = rows, report search; invalid input (future times, report before notice, temperature without unit / impossible, duplicate submit, unknown case, form defaults "Not checked"); **malformed stored data** (invalid JSON kept aside unchanged, non-object entries dropped, missing ids repaired, logged); regression of costs (treatment + consultation fees, no double count), feed, milk review (none for a bull), deletion guards and stock history; emergency/danger-sign urgency and advice wording; **fresh install keeps every module after restart** |
| `test/farm_erp_test.dart` | 28 | passed | Hand-checked P&L (consumption vs purchase feed basis), cash flow ≠ profit, stocking recognised in its month, monthly totals, revenue sharing for bulk milk, shared-cost allocation (equal / head count), cost per litre and per egg, depreciation and book value on sale, species report reconciles to farm total, filters & excluded overhead, CSV row/column parity for all 16 reports, feed issue/edit/delete with no double deduction (incl. g→kg), negative stock refused, manual feed, purchases/wastage/physical count, system movements locked, wastage cost, batch head-count flow, unsold stock & overselling refused, withheld milk not saleable, sale totals/payments/outstanding, Dead/Sold status and restore on delete, archive instead of delete, duplicate expense guards, configurable species, persistence after restart, automatic backup before demo load, migration of old data, demo FCR/laying rate/biomass |
| `test/cow_tracking_test.dart` | 27 | passed | Per-animal feed (individual and group share), milk totals, daily series, withdrawal, stock links, semen straws, weights, form validation, reproduction history, calving workflow, semen suitability rules, breeding reminders |
| `test/owner_features_test.dart` | 13 | passed | Alerts from data, mark-read per user, role-filtered alerts, dashboard figures, P&L total = net sales, CSV export, form validation, activity log author, farm profile persistence, backup/restore validation, owner-only restore |
| `test/auth_test.dart` | 13 | passed | Three roles only, demo sign-in per role, hashed passwords, wrong password/role, session persistence, role navigation (worker has no money screens), user management, own password change, **migration of retired vet/accountant accounts to Farm Worker** |
| `test/widget_test.dart` | 5 | passed | Module registry covers demo columns, record helpers, CRUD round-trip with role checks, status filters |
| `test/app_smoke_test.dart` | 2 | passed | Full UI drive at tablet size (sign-in validation; every section opens; reports + batch drill-down; **Animal Health dashboard → Report Animal Illness with a life-threatening sign (emergency warning shown) → saved → listed as urgent → case details → recovery screen**; daily feed entry through the form reduces stock by exactly the amount; notifications; milk form validation; animal profile + semen check + timeline; users, farm profile, activity log, backup; sign-out; worker sign-in sees no Reports/Users) and at **360 × 740 phone size** (every section via the grouped More menu, animal profile, calving sheet, all settings pages) — any layout overflow fails these tests |

## Problems found and fixed during QA

- **Data loss on restart (existed before this task):** on a fresh install, demo modules the user never edited were not written to storage, so after a restart they came back empty. Every module is now saved on first start; a regression test covers it.
- Health date checks used the device clock instead of the farm clock; recovery on today's date was compared with the time of day.
- A long health-status chip overflowed on a 360 px phone (caught by the phone UI test) — chips now wrap.
- Corrupted saved JSON used to crash the app at start; it is now kept aside and logged.

- Demo sales with later part-payments were seeded as "Due". Seed data now goes through the same calculation as user entries.
- The farm profile form would have reset the calculation settings when saved. It now updates only its own fields.
- The bottom navigation used section indexes after tabs became role-dependent. Tabs are now mapped explicitly.
- Old tests that edited inventory quantity directly now use stock transactions, because direct edits are deliberately locked to preserve history.


## Full-project review & QA pass (2026-10-11)

Commands run: `flutter analyze` → **No issues found**; `flutter test` → **130 tests, all passed** (the 108 earlier tests plus 22 new QA tests). No APK was built in this pass.

New QA test files:

| File | Tests | Covers |
|---|---|---|
| `test/qa_screens_test.dart` | 4 | For **each role** (Owner, Manager, Worker) on a 360 × 640 phone: dashboard, Animal Health, notifications, settings pages, the list + new form + 3 edit forms of every module the role can open, every animal profile and health history, every batch profile, every illness case, and every report through the report picker. Every report kind × 5 date presets × 6 filters builds with equal-width rows, no NaN/Infinity, and CSV = rows |
| `test/qa_rules_test.dart` | 17 | Reproduces each issue below and checks the fix |
| `test/qa_data_integrity_test.dart` | 1 | Demo data: unique ids and names, required fields, every reference resolves, choices valid, stock = sum of its movements, no negative stock/head count/product stock, Dead/Sold statuses match their records, and **every record re-saves under the rules** |

Issues found and fixed:

- **Duplicate names and codes were accepted** (inventory item, species, location, customer, batch, semen code, animal tag). Feed and medicine take stock by item name, so a duplicate could take stock from the wrong item. They are now refused with a clear message; values are trimmed; untagged animals are still allowed.
- **Renaming broke links.** Renaming a location, species, customer or semen code left animals, batches, expenses, sales, payments and AI services pointing at the old name. These now follow the rename, as inventory items already did. Renamed animals and batches also update the "ID · Name" shown in other records.
- Treatment cards on the illness page hid the tap ripple of their dose rows (a decorated box over the ink). Changed to a Material. Treatments with more than 8 doses now say how many more are in the Medication Log.
- "Reorder level" accepted any text, and text never triggered a low-stock alert. It is now a number field.
- Payment-due alerts showed the full sale amount and an empty description. They now show the amount still due, the total, and the product.
- Record search matched hidden internal fields (timestamps). It now searches only visible fields.
- Illness cases, follow-ups, treatments and doses were not sorted by date in their lists (they have no `date` field). They now sort by their own date.

## Not verified

- "Call vet" uses `url_launcher` (opens the dialer; Android manifest declares the tel/DIAL query). It cannot run in widget tests, so it was **not verified on a device** — the code falls back to "copy number" when no dialer is available.
- Reminders are **in-app only** (Notifications screen, dashboard, bell badge). No native local notifications were added, so nothing appears while the app is closed.

- **Not run on a physical device or emulator** in this session. The debug APK was built but not installed. Please test on your phone: install, sign in as each role, add a feed record, and force-close and reopen to confirm persistence.
- No performance test with very large datasets (many thousands of records per module).
- `python tool/qa_static.py` was not run, because Python is not installed in this environment.

## Manual checklist for device testing

- [ ] Install `app-debug.apk`; sign in as Owner, Manager and Worker
- [ ] Worker: confirm no Sales/Expenses/Reports and no money figures in profiles
- [ ] Add a feed record from inventory, edit its quantity, then delete it, checking the stock after each step
- [ ] Record eggs, sell some, and check unsold stock in Reports → Production & unsold stock
- [ ] Record a mortality in a batch and confirm the head count drops
- [ ] Reports: change dates/filters, Copy CSV, and paste into a spreadsheet
- [ ] Force-close and relaunch to confirm the data is still there
- [ ] Settings → Load demo data, then Backup & restore → Restore automatic backup

## Hive storage, role access and My profile (2026-10-11)

Commands run: `flutter pub add hive_ce hive_ce_flutter` → OK; `flutter analyze` → **No issues found**; `flutter test` → **138 tests, all passed**. No APK was built in this pass, so Hive has **not yet been verified on a device** (widget tests use an in-memory Hive box).

- Storage moved from SharedPreferences to a Hive box. Existing data is copied once, unchanged, and logged; the old copy is kept; a later start never copies it over newer Hive data (tested).
- Per-module access: `UserRole.canEditModule` / `accessLabel`. Farm Worker: Inventory items view only, no delete. Enforced in the list (no Add/Edit/Delete), the form (read-only, no Save) and the form controller (save refused, also when signed out).
- New **My profile** page (MVC: `MyProfileController` + `my_profile_view.dart`).
- `test/profile_access_test.dart` (8 tests): demo data in Hive and after restart; legacy migration; access rules per role; worker read-only inventory; signed-out cannot save; profile lists exactly the visible sections with live counts and own changes; **UI: worker opens My profile → Inventory shows View only → edits a milk record → value saved in Hive → change listed on the profile**; an open cow profile updates at once when the animal is renamed. `qa_screens_test.dart` also renders My profile for each role on a phone.
- Existing tests now sign in before using forms, because forms are read-only for a signed-out user.

## 10 demo records per screen, shared changes, My profile cleanup (2026-10-11)

`flutter analyze` → **No issues found**; `flutter test` → **141 tests, all passed**. No APK built in this pass.

- Checked: all 27 record screens already had ≥10 demo records on a fresh install; the **Activity log was empty** (so "Your recent changes" was too). Added a 14-entry demo activity log (`lib/data/demo_activity.dart`); each entry points at an existing demo record and a demo user, never in the future.
- Installs created with an older demo set did not get the new records. Added `demo_data_version`: an unedited older demo farm is upgraded once (automatic backup first); a farm with any added or edited record is never replaced, and one notice explains Settings → Reset demo data.
- My profile: the "Your farm data" section was removed (with its unused records screen).
- `test/demo_data_test.dart` (3): ≥10 records per screen and in Hive, 10 accounts per role, demo activity valid; untouched old demo upgraded once with backup; edited farm kept, notice once, reset loads the full set.
- `test/profile_access_test.dart`: **UI: worker edits a milk record → signs out → a different manager (manager05) sees 12.5, changes it to 11 → owner sees 11, and the Activity log names both users.** Also checks the removed section is gone.

## DeshIT-BD refinement: Farm Owner & Farm Manager, livestock only (2026-10-11)

Commands run in this environment: `flutter analyze` → **No issues found**; `flutter test` → **151 tests, all passed**. **No APK was built and nothing was run on a device in this round**, so the Hive storage and the new screens have only been verified in Flutter's test environment.

### Audit before changes (what was found)
- Three roles (Owner, Manager, Worker). The Manager had almost the Owner's rights: finance, the activity log, delete and archive.
- Permissions lived on the role only, and were mostly checked in screens. `canSeeFinance` was **not checked anywhere in Reports**. That was harmless before, because Workers could not open Reports, but it would have exposed profit reports to managers once Reports opened to them.
- Poultry, fish and bee batches were part of every layer: menus, forms, demo data, dashboard ("Birds & fish", eggs) and reports.
- One generic dashboard. Green branding and no company details.

### What was changed
- **Roles:** Farm Owner and Farm Manager only.
  - The owner can give each manager rights: sales & payments, purchases, expenses, financial summaries.
  - Older Worker, Vet and Accountant accounts are migrated to Manager with no money rights, and the change is logged.
  - Demo accounts: 10 owners and 10 managers with mixed rights.
- **Permission checks** are in one place (`AccessPolicy`). The data layer enforces them: `FarmController` refuses add, edit, delete, archive, settings, reset and restore when not allowed. Lists hide Add/Edit/Delete, and forms open read-only.
- **Livestock only:**
  - The batch modules (poultry, fish, bees) are out of scope: no role opens them, and they are in no menu or report.
  - Batch fields are hidden in forms, except on older records that already hold a value.
  - Products, units, location kinds, feed categories, species categories and expense options are livestock-only.
  - Older saved data is never deleted.
- **Demo farm rewritten as livestock-only:**
  - fattening bulls sold at the haat, dead and transferred animals, manure, wool and offspring production;
  - cattle, goat and sheep vaccinations, and livestock customers and suppliers;
  - at least 10 records on every screen.
  - An unedited older demo farm is upgraded once (with a backup first). A farm with user changes is never replaced.
- **Separate Owner and Manager dashboards** (see README). A new report row gives the cost per kg live weight for each fattened animal sold.
- **Reports:**
  - Financial reports (P&L, monthly, cash flow, animal and species profit, cost per unit, sales, most expensive, health costs) are shown only with finance rights.
  - The batch report is removed.
  - Raw record export is limited to sections the user can open.
- **Branding:**
  - DeshIT-BD navy, orange actions, green/amber/red status colours.
  - Company website, phone/WhatsApp and email are in Settings → Contact and on the sign-in screen. Each opens the matching app, or copies the detail if no app can open it.
  - Android manifest queries were added for https and mailto.

### Tests added or changed
| File | What it checks |
|---|---|
| `dashboard_test.dart` (new, 5) | Owner figures equal the saved records: herd by status, milk today/7 days/month, sales, expenses, purchases, feed cost, revenue and profit (= FinanceEngine), receivables, stock value, 6-month trend (= P&L revenue). A new sale and expense update the dashboard at once. Manager: cows not milked today, tasks due, no money and no sales activity without the right. Each role sees its own dashboard |
| `auth_test.dart` (20) | Two roles only; role-permission matrix (owner, operations-only manager, each grant, all grants still without settings or users); navigation follows rights; owner grants and changes rights; managers cannot manage users; Worker/Vet/Accountant migrate to Manager without rights; 10 demo accounts per role with the documented rights |
| `profile_access_test.dart` (9) | **Data-layer enforcement**: an operations-only manager can add milk but not sales, expenses, setup changes, deletes, archive, settings, reset or restore; a manager with rights can add sales and expenses but not delete; the owner can; signed out, nothing. UI: one manager edits milk → another manager sees and changes it → the owner sees it, and the activity log names both |
| `qa_screens_test.dart` (5) | Every screen, form, profile and allowed report renders on a 360 × 640 phone for the owner and three kinds of manager. Financial reports appear only with finance rights. No batch report |
| `demo_data_test.dart` (3) | ≥ 10 demo records per livestock screen; no poultry, fish or bee records, species or products; Active, Sold, Dead and Transferred animals present; demo upgrade rules |
| Others | Updated for the livestock demo: group rations, vaccination costs, backup counts, species pickers, and the manager in place of the worker |

### Issues found and fixed while doing this
- Financial reports were not permission-checked (see the audit). They now are, in the report list and again when a report is built.
- The manager dashboard listed money entries in "recent activity" for managers without money rights. Those entries are now filtered out, along with account and settings entries.
- The navy app bar would have made the grey farm-name subtitle unreadable. It now uses light text.
- `dart format` produced five lint warnings (braces). These were fixed.

### Modified files
- New:
  - `lib/models/access_policy.dart`, `lib/core/company.dart`, `lib/services/link_service.dart`;
  - `lib/views/owner_dashboard_view.dart`, `lib/views/manager_dashboard_view.dart`;
  - `lib/views/widgets/dashboard_widgets.dart`, `lib/views/widgets/company_card.dart`;
  - `test/dashboard_test.dart`.
- Changed (logic or text):
  - Models: `user_role`, `app_user`, `farm_module`, `app_section`, `farm_record`.
  - Data: `demo_users`, `demo_data`, `demo_extras`, `demo_activity`.
  - Controllers: `auth_controller`, `users_controller`, `farm_controller`, `navigation_controller`, `alerts_controller`, `records_controller`, `record_form_controller`, `reports_controller`, `dashboard_controller`, `settings_controller`, `my_profile_controller`.
  - Utilities and theme: `units`, `app_colors`, `app_theme`.
  - Views: `app.dart`, `app_shell`, `login_view`, `settings_view`, `users_view`, `my_profile_view`, `record_form_view`, `reports_view`, `dashboard_view`, `health_dashboard_view`, `illness_details_view`, `cow_profile_view`, `batch_profile_view`, `account_views`, `health_reports`.
  - Other: `AndroidManifest.xml`, `README.md`, all test files.
- Formatting only (`dart format -l 200`): the remaining files under `lib/` and `test/`.

### Known issues and limitations
- Not run on a phone in this round. Please install, then:
  1. sign in as `owner` and `manager03`;
  2. check the two dashboards, and that `manager03` sees no Sales, Expenses or profit;
  3. in Users & roles, tick a right for a manager and sign in as them;
  4. restart the app to confirm the data is still there (Hive).
- Local storage only: no sync between phones, cloud backup or multi-farm support.
- Reminders are in-app only.

## Owner / Manager responsibilities: approvals, budget, team (2026-10-11)

`flutter analyze` → **No issues found**; `flutter test` → **160 tests, all passed**. No APK built; not run on a device.

The spec was compared with the app. Already in place: both dashboards, income, expense and profit, receivables, trends and the monthly P&L, owner-managed permissions, and daily feed, milk, health, breeding and stock. **Added:**
- **Payables:** what the farm owes (unpaid expenses and purchases).
- **Monthly budget**, with an alert at 90% and when it is exceeded.
- **Owner approval limit for large expenses and purchases.** Items above it are pending until approved, never counted while pending or after rejection, and only the owner can decide.
- **Requests and approvals.**
- **Managers' daily or monthly reports**, with summaries filled in from the records, reviewed by the owner.
- **Staff list and daily task assignment and checking.**
- **Yearly summary and animal purchases & sales reports.**
- **Alerts** for the owner (decisions waiting, budget) and for managers (decisions on their requests, open tasks).
- **Multi-line text fields** for notes and summaries.

Not implemented: **multiple farms**. The data model holds one farm, and adding several would need per-farm data and a switcher.

Also changed (in addition to the modified-files list in the previous section):
- New files:
  - `lib/controllers/approvals_controller.dart`, `lib/controllers/operations_summary.dart`;
  - `lib/views/approvals_view.dart`, `lib/data/demo_team.dart`;
  - `test/owner_control_test.dart`.
- Updated files:
  - Models: `field_spec` (owner-only fields, staff picker), `farm_profile` (limit, budget), `farm_module` (4 modules, approval fields), `access_policy`, `app_section`.
  - Controllers: `farm_controller` (approval logic, owner-only enforcement, `decide`, staff links), `finance_engine`, `health_reports`, `dashboard_controller`, `alerts_controller`, `records_controller`, `record_form_controller`, `reports_controller`, `account_controllers`.
  - Views: `owner_dashboard_view`, `manager_dashboard_view`, `app_shell`, `record_form_view`, `account_views`.
  - Demo data and tests.

| New test (`owner_control_test.dart`, 9) | Checks |
|---|---|
| Approvals | A manager's ৳30 000 expense is pending even if marked approved; not counted; the manager cannot decide; a rejection needs a reason; approval makes it count; raising an approved amount sends it back; a rejected expense never counts; the owner's ৳90 000 needs no approval; purchases follow the same rule |
| Budget and payables | Budget used = approved expenses ÷ budget; payables = unpaid, not-rejected expenses and purchases; one owner alert per waiting item |
| Requests | Pending by default with the requester's name; a manager cannot approve; the owner's decision records who decided; the manager gets an alert and sees it on Approvals |
| Reports | The daily summary shows today's milk from the records; switching to Monthly refreshes it; the manager's own text is kept; status is owner-only; the owner marks it reviewed with a comment |
| Staff and tasks | A manager cannot hire, and wages are hidden without the finance right; "Not done" needs a reason; marking done records who checked; renaming staff updates their tasks; staff with tasks cannot be deleted |
| Owner reports | The yearly summary adds up to the all-time revenue; animal trade result = net sale − purchase − keeping cost (Kalu: 143 500 net); no trade report without the finance right |

Fix made while testing: the smoke test's page-scroller helper picked up the scroller inside the new multi-line text fields. It now ignores scrollers inside text fields. This was a test-only issue.

## Remembered sign-in, buttons and filters (2026-10-11)

`flutter analyze` → **No issues found**; `flutter test` → **173 tests, all passed** (13 new in `test/qa_filters_test.dart`). No APK built in this round.

**Sign-in.**
- Each role fills in its own saved username and password: the demo account at first, then the last successful sign-in for that role.
- It is saved in Hive and survives a restart. Password changes and resets update it. Deleting, disabling or moving the account to another role forgets it. Unticking *Remember* forgets it.
- The save happens inside sign-in, before the screen changes, so a closing sign-in screen is never updated.

**Audit of buttons and filters.** Tested and confirmed working:
- Record lists: every status filter of every section shows exactly the matching records; search; sort.
- Health dashboard filters.
- Report filters: species, animal, location, product, date presets, search.
- Cow profile period chips.
- Every dashboard tile and section link, for the owner and two kinds of manager. Each opens a section that user may open.

**Issues found and fixed:**
- The Health dashboard tiles *Reported sick*, *Urgent vet attention* and *Today's activities* looked tappable but did nothing.
  - The first two now filter the animal list (new choices in the Health status filter).
  - The third scrolls to *Today & overdue*.
- The *Report* and *Records to export* dropdowns could show an old choice when the app changed the report (for example, a report the user may not open). They are now keyed so they always show the report actually built.
