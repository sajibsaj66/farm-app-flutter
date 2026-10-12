# DeshIT-BD Farm Management — Flutter (offline, MVC)

Livestock and cattle farm management for **Farm Owners** and **Farm Managers**: dairy farms, cattle rearing, cattle fattening and mixed livestock (cattle, buffalo, goats, sheep and other livestock). It runs fully **offline**: every record is stored on the device in a local Hive database, and no backend or internet connection is needed. Currency defaults to **৳ (BDT)**.

**DeshIT-BD** · [www.deshit-bd.com](https://www.deshit-bd.com) · Phone / WhatsApp: +880 1537-570379 · info@deshit-bd.com

Poultry, fisheries, aquaculture, bee-keeping and crop modules are **not** part of this system.

## Setup

Requirements: Flutter 3.47 or newer (Dart 3.13), Android SDK.

```bash
flutter pub get
```

```bash
flutter run
```

Quality checks:

```bash
flutter analyze
```

```bash
flutter test
```

## Sign in

Choose **Farm Owner** or **Farm Manager** on the sign-in screen and enter a username and password, or tap *Use demo … account*. Demo accounts (10 per role):

| Username | Password | Role | Rights |
|---|---|---|---|
| `owner`, `owner02`…`owner10` | `owner123`, then `<username>pass` | Farm Owner | Everything |
| `manager` | `manager123` | Farm Manager | Operations + sales, purchases, expenses |
| `manager02` | `manager02pass` | Farm Manager | Operations + sales, purchases, expenses + financial summaries |
| `manager03`, `05`, `07`, `09` | `<username>pass` | Farm Manager | Operations only |
| `manager04`, `06`, `08`, `10` | `<username>pass` | Farm Manager | Operations + sales |

**Remembered sign-in:** choosing *Farm Owner* or *Farm Manager* fills in that role's username and password. The first time these are the demo account; after that, the last successful sign-in for that role (when *Remember … sign-in on this device* is ticked, the default). They are updated when a password is changed or reset, and forgotten when the account is deleted, disabled or moved to another role, or when *Remember* is unticked.

Passwords are stored as salted SHA-256 hashes. Accounts from older versions with the retired roles (Farm Worker, Veterinarian, Accountant) become **Farm Managers without money rights**, and the change is written to the activity log.

## Role-permission matrix

The Farm Owner gives each manager extra rights in **Settings → Users & roles** (tick boxes on the user form).

| Area | Farm Owner | Farm Manager | Manager with the right ticked |
|---|---|---|---|
| Animals, weights, breeding, semen, mortality | View, add, edit, delete | View, add, edit | — |
| Feed records, inventory, stock transactions | View, add, edit, delete | View, add, edit | — |
| Milk, production, product usage | View, add, edit, delete | View, add, edit | — |
| Animal health: illness, consultations, treatments, doses, follow-ups, vaccinations; close a case | Yes | Yes | — |
| Species and locations (farm setup) | View, add, edit, delete | **View only** | — |
| Sales, payments received, customers | Yes | No | *Record sales & payments* |
| Purchases | Yes | No | *Record purchases* |
| Expenses | Yes | No | *Record expenses* |
| Profit, costs, income: dashboard money cards, financial reports, cost/profit in animal profiles | Yes | No | *See financial summaries* |
| Operational reports (feed, production, mortality, breeding, health, inventory, record export) | Yes | Yes | — |
| Staff list (hire, wages) | View, add, edit, delete | View only (wages hidden without the finance right) | — |
| Daily staff tasks: assign, mark done, not done with a reason | Yes | Yes | — |
| Requests to the owner (feed, equipment, animal purchase, expansion…) | Approve or reject | Raise, and see the decision | — |
| Daily or monthly report to the owner | Review and comment | Send (summary filled in from the records) | — |
| Expense or purchase above the owner's approval limit | Approve or reject (with a reason) | Saved as *Pending owner approval*, not counted until approved | — |
| Monthly budget and approval limit | Set | No | — |
| Delete or archive records | Yes | No | — |
| Users & roles, farm profile, calculation and health settings | Yes | No | — |
| Backup & restore, load demo data, full activity log | Yes | No | — |
| My profile, change own password, notifications | Yes | Yes | — |

These rules live in one place, `lib/models/access_policy.dart`. They are **enforced in the data layer** (`FarmController` refuses any write the signed-in user is not allowed to make), not only by hiding buttons. Forms the user may not change open read-only without a Save button.

## Dashboards

**Owner dashboard: business performance.**
- Herd: animals on the farm, sold, transferred and deceased, plus confirmed pregnancies.
- Milk today, in the last 7 days and this month, with milk withheld during a medicine withdrawal.
- This month's money:
  - net sales, total costs and operating profit or loss;
  - feed consumed (kg and cost) and vet & treatment costs;
  - expenses recorded, and supplier purchases with the amount still due;
  - what customers owe, and net cash flow.
- Inventory: stock value and low-stock items.
- A six-month trend of milk, revenue, costs and result.
- Alerts, and the managers' recent recorded activity.

**Manager dashboard: today's operations.**
- Lactating cows not yet milked today.
- Feed entries today.
- Open and urgent illness cases.
- Doses, follow-ups and vaccinations due today or overdue.
- Low stock, and pending reminders.
- Quick entry buttons, limited to what the manager may record.
- Recent activity. A manager sees no money or account entries here.
- A money summary only if the owner gave the *financial summaries* right.

All figures are calculated from saved records. Operating profit is an estimate from the records entered (see *Accounting model*).

## Modules

| # | Module | Status |
|---|---|---|
| 1 | Owner dashboard | Complete |
| 2 | Manager dashboard | Complete |
| 3 | Animal registration & management (profile, timeline, family, archive) | Complete |
| 4 | Daily feed management (individual or group rations, stock-linked) | Complete |
| 5 | Milk production (per shift, quality, withdrawal → Withheld) | Complete |
| 6 | Animal health & treatment (illness → vet → treatment → doses → follow-up → outcome) | Complete |
| 7 | Vaccination & breeding (schedules, AI with semen stock, pregnancy, calving) | Complete |
| 8 | Feed inventory (stock movements, purchases, wastage, physical count) | Complete |
| 9 | Animal purchases & sales (purchase price on the animal; live-animal sales mark it Sold) | Complete |
| 10 | Farm expenses (charged to an animal, a location, or farm-wide with allocation) | Complete |
| 11 | Income & sales records (sales, payments received, customers' outstanding) | Complete |
| 12 | Financial summary (P&L, monthly, cash flow, cost per litre / per kg live weight) | Complete |
| 13 | Operational reports (feed, production, mortality, breeding, health, inventory, CSV) | Complete |
| 14 | Activity history (who changed what) | Complete |
| 15 | User roles & permissions (owner-granted manager rights) | Complete |
| 16 | Farm settings & data backup (copy/paste JSON backup, automatic backup before demo load) | Complete — local only |
| 17 | Approvals (large expenses and purchases, requests, managers' reports) | Complete |
| 18 | Budget and payables (monthly budget, what the farm owes) | Complete |
| 19 | Staff and daily task assignment | Complete |
| 20 | Manager → owner requests and daily/monthly reports | Complete |
| 21 | Yearly summary and animal purchases & sales reports | Complete |

**Not implemented:**
- **More than one farm.** The app holds one farm's data, so the owner cannot compare several farms. This needs a separate data set per farm and a farm switcher.
- Online sync, cloud backup or multi-device use.
- Phone notifications while the app is closed. Reminders show inside the app.
- SMS or email sending.
- Photo upload.
- RFID or QR scanning.
- Payroll, equipment maintenance, feed formulation and double-entry accounting.

## Accounting model

| Figure | How it is calculated |
|---|---|
| Feed cost | quantity consumed × unit price on the feed record |
| Net sales (revenue) | quantity × price − discount − sales deductions, on the sale date |
| Operating profit | recognised revenue − recognised operating costs |
| Net cash flow | cash actually received − cash actually paid (**not** profit) |
| Cost per litre | operating cost of the milking animals ÷ litres they produced |
| Cost per kg live weight | for an animal sold live (fattening): its operating cost in the period ÷ its last recorded weight |

Rules against double counting:
- **Feed cost basis** (Settings → Calculation settings). *When fed* (default) counts feed records, and Feed expenses are treated as stock bought. *When bought* counts Feed expenses. Feed is never counted both ways.
- **Treatment costs** come from health records, treatment plans and consultation fees. A matching vet expense is refused.
- **An animal's purchase price is an asset**, not a daily cost. It is kept as an asset (book value charged when the animal is sold or dies) or depreciated straight-line.
- **Purchases** are a log of supplier orders. Their cost reaches profit through expenses and stock, so it is not added again.
- **Shared expenses** are allocated by the method chosen on each expense: none, equal per animal, by head count, by feed cost, or by production value.

## Data and storage

- All data is stored in a local **Hive** box on the device. Data from older versions saved in SharedPreferences is copied across once, unchanged.
- Every record has a stable ID. Integrity rules:
  - stock can never go negative;
  - you cannot sell more than is in stock, or a sold or dead animal;
  - payments can never exceed what is owed;
  - names and codes (stock items, species, locations, customers, semen codes, ear tags) must be unique;
  - renaming something updates every record that refers to it;
  - records that others depend on cannot be deleted (archive instead).
- All users on one phone share the same data, so a saved change appears on every screen and for every user at once.
- **Backup & restore** (owner): copy all data as JSON (no passwords) and restore it, with validation. Loading demo data first saves an automatic backup.
- **Demo farm:**
  - A fresh install has at least 10 demo records on every screen, 10 accounts per role and a demo activity log.
  - Records left over from older versions are kept but hidden: poultry, fish and bee batches, and their batch fields.

## Project structure (MVC)

```
lib/
  models/       FarmModule (field specs), FarmRecord, FieldSpec, FarmProfile, finance value objects,
                UserRole, AppUser, AccessPolicy (role-permission matrix), AppSection (navigation)
  services/     LocalStorageService (Hive), PhoneService, LinkService
  controllers/  FarmController — repository, business rules, permission checks, migration, backup
                FinanceEngine — revenue, costs, allocation, cash flow, P&L
                DashboardController — owner and manager dashboard figures
                Herd/Cow/Health analytics, Reports, Alerts, Records, RecordForm, Users, MyProfile…
  views/        owner and manager dashboards, records list & form, animal profile, health, reports,
                settings, users, my profile, login; widgets (dashboard, company contact card…)
  core/         theme (DeshIT-BD colours), company details, utilities
  data/         demo farm (relative to today), demo activity, demo accounts
```

Views contain no business or financial logic. They show what controllers compute.

## Known limitations

- Remembered sign-in details, including the password, are kept in the app's local storage without encryption. Anyone who can unlock the phone and open the app can sign in with them. Untick *Remember* on shared phones.
- Local, single-device storage: no sync between phones, no multi-farm or branch separation, and login is not a substitute for server authentication.
- Group rations are shared by the animals in the group **now**.
- Expected calving uses a cattle gestation of 283 days for all species.
- Not yet run on a physical device in this round (see QA-REPORT.md).

## Owner control and team workflow

- **Approval limit and monthly budget** (Settings → Calculation settings, owner only). Defaults: ৳20 000 and ৳150 000.
- **Large spending:**
  - A manager's expense or purchase above the limit is saved as *Pending owner approval*. It is not counted in profit, cash flow, the budget or payables until the owner approves it.
  - A rejected one is never counted.
  - If a manager changes the amount of an approved item, it goes back for approval.
  - The owner's own entries need no approval.
- **Approvals screen** (Team & approvals → Approvals):
  - The owner approves or rejects large expenses, purchases and requests (a rejection needs a reason), and marks managers' reports reviewed with a comment.
  - A manager sees what is waiting and the decisions on their own items.
  - These decisions can only be made by the owner, and the data layer enforces it.
- **Requests:** a manager asks for feed or supplies, equipment, an animal purchase, a large expense or an expansion, with an estimated cost and a needed-by date. The owner decides, and the manager gets an alert.
- **Reports to the owner:**
  - The summary is filled in from the records: milk, feed, health, deaths, low stock and staff tasks, plus sales and expenses for a manager with those rights.
  - Changing the date or period refreshes the summary, but a manager's own text is never overwritten.
- **Staff and daily tasks:**
  - The owner manages the staff list. Staff are farm hands without app logins.
  - The manager assigns tasks by shift and marks them done (the app records who checked), or not done with a reason.
  - Both dashboards show today's progress.
- **Owner dashboard additions:** items waiting for a decision, budget used, what the farm owes, expenses awaiting approval, and staff tasks today.
- **Manager dashboard additions:** staff tasks (tap to mark done), sending today's report, asking the owner, and the status of their requests.
