# shrADD — Handoff Doc

Paste this whole file as your first message in a new chat to pick up exactly where this session left off. No other context needed.

## What this is

**shrADD.** — a personal iOS expense tracker (SwiftUI) backed by Firebase Firestore, with a Google Apps Script pipeline that reads DBS + Trust bank alert emails from Gmail and writes transactions to Firestore automatically.

- Project path: `/Users/shrad1601/Downloads/expense-tracker`
- Not a git repo
- Bundle ID: `com.shraddhasriram.expensetracker.app`
- Firebase/Firestore project ID: `expense-tracker-7d7f1`
- Apps Script file: `apps-script/Code.gs` (paste-and-run in the Apps Script web editor — not deployed via CLI)

## Architecture

- SwiftUI + MVVM. `TransactionListViewModel` (`ExpenseTracker/Views/TransactionListViewModel.swift`) is the single shared `@MainActor ObservableObject` owning all state, created once in `RootTabView.swift`.
- Protocol-oriented repositories, each with a Firestore + Mock implementation, in `ExpenseTracker/Data/`: `TransactionRepository`, `BudgetRepository`, `CategoryRepository`, `MerchantRuleRepository`.
- `RootTabView` → 2 tabs: **Transactions** (`TransactionListView.swift`) and **Categories** (`CategoryBreakdownView.swift`).
- Project file (`.xcodeproj/project.pbxproj`) is **hand-maintained** — every new Swift file needs a manual PBXBuildFile/PBXFileReference/PBXGroup/PBXSourcesBuildPhase entry with a generated 24-char hex UUID. `project.yml` (XcodeGen manifest) exists but isn't regenerated automatically; edits have been going directly into the `.pbxproj`.
- Build via `xcodebuild -project ExpenseTracker.xcodeproj -scheme ExpenseTracker -destination 'generic/platform=iOS Simulator' build`. If Xcode throws a PIF/GUID "multiple references" error, quit Xcode, `rm -rf ~/Library/Developer/Xcode/DerivedData/ExpenseTracker-*` and any `xcuserdata`, reopen.
- iOS Simulator MCP tool coordinate space is **393×852 points**, origin top-left — NOT the same as screenshot pixel dimensions. Screenshots render larger; roughly divide your visual pixel estimate by ~2.35 to get tap coordinates. Always verify UI changes visually via screenshot, not just "build succeeded."

## Fully built and working

**App:**
- Transactions tab: day-grouped, month-navigable list, manual add/edit/delete, swipe to delete
- Categories tab: pie chart (month-navigable, tap slice to drill in), per-category color + budget, delete category (via tapping a category card, or via "Manage" button top-right which lists ALL categories including unused ones — the pie chart only shows categories with spend that month)
- Custom categories, custom per-category colors, custom app accent color, light/dark mode (system or manual)
- Overall monthly budget with progress bar + pace indicator ("on track" vs "spending faster than planned" — compares spend-so-far to a day-of-month-proportional expected spend)
- Auto-categorization rules, manageable in-app: Settings → Auto-Categorization Rules ("if merchant contains X → category Y")
- **Income logging**: Expense/Income segmented toggle in the add/edit sheet. Income shows in green with a "+" prefix and an "Income" tag instead of a category. Budgets, pace, monthly spend total, and the category pie chart are all **expense-only** — income never nets against them, it only shows as a separate "+$X income" line on the total card. Day-header totals in the transaction list are also expense-only (income rows just show inline with their own "+" amount).
- Custom "S+" app icon. Runs on a physical iPhone via free Apple ID (7-day resign limit — needs periodic rebuild from Xcode) and in Simulator.

**Automation (`apps-script/Code.gs`):**
- `processAlerts()` — the 5-minute-trigger entry point. Searches Gmail for DBS ("Card Transaction Alert" / "Transaction Alerts") and Trust ("Yay! Transaction successful") subjects, parses each, writes to Firestore idempotently (Gmail message ID as doc ID, PATCH not POST), sends Discord notifications, checks overall budget thresholds.
- `backfillSilently()` — same pipeline but no Discord notifications, batched at 25 threads/run. Use this whenever a new bank/parser starts matching a backlog of old emails, to avoid a notification flood (this happened once already with Trust).
- Both funnel through `processBatch_(notify, maxThreads)`.
- `checkOverallBudgetThreshold_()` queries **only the current month's transactions** via a Firestore structured query (`fetchTransactionsTotalInRange_`) — this was a deliberate fix after it originally re-read the entire transaction history every 5-minute run and blew through Firestore's free daily read quota (429 RESOURCE_EXHAUSTED).
- Discord webhook notifications: new expense logged, needs categorization (still Uncategorized), budget threshold crossed (80%, then 100%, once per threshold per month — tracked via Script Properties so it doesn't repeat-fire).
- Auto-categorization priority order: **custom rules** (from the app, fetched via `fetchMerchantRules_`) → **hardcoded `MERCHANT_CATEGORIES` dict** → **LLM fallback** (see below) → `Uncategorized`.
- Maintenance functions: `deduplicateTransactions()`, `applyRulesToExistingTransactions()` (retroactively applies current rules to old transactions), `createTrigger()` (recreates the 5-min trigger — **must be re-run any time you rename the trigger's target function**, e.g. this already happened once when `processDbsAlerts` was renamed to `processAlerts`), `debugKey()` (safe private-key diagnostic).

**LLM auto-categorization (Apps Script):**
- `categorizeWithLLM_(merchant, availableCategories)` calls the Anthropic API (`claude-haiku-4-5-20251001`) with the merchant name and the user's real category list, asking for the single best-fit category or "Uncategorized". Only trusts the response if it's literally one of the offered categories — never invents new ones.
- Only fires when rules AND the hardcoded dict both miss (fallback-only, per user's explicit choice — not a per-transaction cost).
- Auto-applies the result (per user's explicit choice — no manual confirmation step).
- Needs `ANTHROPIC_API_KEY` set in Apps Script's **Project Settings → Script Properties**. User said they already have a key — **unclear if they've actually added it to Script Properties yet**. Check this first in a new session.
- `testLLMCategorization()` — safe dry-run test function, logs a categorization guess for a fake merchant without writing anything.
- `categorizeUncategorizedWithLLM()` — retroactive pass over existing "Uncategorized" transactions, capped at 30/run.

## In progress / not yet finished

### On-device ML classifier (was mid-teaching-walkthrough when this handoff was requested)

The user explicitly asked to **learn this step by step rather than have it built for them** — continue in that spirit, don't just dump finished code.

What's done so far, all saved in `/Users/shrad1601/Downloads/expense-tracker/ml/`:
- `training_data.json` — 233 `{text, label}` pairs (merchant name → category), exported directly from Firestore via unauthenticated REST reads (see security note below), filtered to expense-type transactions with a real (non-"Uncategorized") category.
- `train_classifier.swift` — a Swift script (run via `swift train_classifier.swift` on macOS, using `import CreateML`) that loads that JSON into an `MLDataTable`, trains an `MLTextClassifier` (MaxEnt/logistic regression under the hood), and writes out a `.mlmodel`.
- `MerchantCategoryClassifier.mlmodel` — the trained model. **Result: 100% training accuracy, 82% validation accuracy** on the held-out split. 100% training accuracy is expected/uninteresting (model grading itself on data it memorized); 82% validation accuracy is the real signal and is a reasonable result given only 233 examples with several categories (Beauty, Gifts) having just 1 example each.

**What's already been explained to the user** (don't re-explain unless asked): the JSON training format, what `MLDataTable` and `MLTextClassifier` do, what MaxEnt training is, and — most importantly — *why* training accuracy (100%) and validation accuracy (82%) are different things and which one actually matters.

**Not yet done — the next teaching step, whenever resumed:**
1. How a `.mlmodel` file gets added to an Xcode project (drag into project, Xcode auto-compiles to `.mlmodelc`, generates a Swift class).
2. Writing the Core ML inference call (`NLModel` or the generated class's `.predictedLabel(for:)`) to get a category guess from a merchant string, on-device, no network call.
3. Wiring it into the categorization pipeline as another tier — proposed order was: rules → local ML model → cloud LLM → Uncategorized (exact placement still to be decided/confirmed with the user).
4. A retraining strategy — no automatic retraining exists yet. Plan discussed but not built: re-run the export + `train_classifier.swift` periodically (piggybacking on the existing habit of periodic app rebuilds for the free Apple ID's 7-day resign limit) and re-bundle the updated `.mlmodel`.

## Known issues / flagged but not yet fixed

- **Firestore has no security rules requiring auth** — confirmed by successfully reading the entire `transactions` collection via a plain unauthenticated `curl` to the REST API (used to export the ML training data). Anyone with the project ID (`expense-tracker-7d7f1`) can currently read (and possibly write) the whole database with zero authentication. Flagged to the user; not yet fixed. Worth doing before this goes any further, especially before making the ML training data pipeline routine.
- DBS PASSION card email parsing — explicitly parked by the user ("lets screw the passion card for now"), only the standard DBS card format + Trust are parsed.
- Income auto-parsing from bank credit/deposit alert emails — user wants "manual + auto-parsed", manual is done, auto-parse needs a sample credit-alert email from the user before it can be built (same pattern as how the Trust card parser was built from a screenshot).

## Explicitly parked (only build if user asks again)

- Multi-user / shared expense tracker (would need Firebase Auth + per-user data isolation — discussed as a real feature, not a toggle)
- Custom savings goals, investments tracking
- Weekly-rebuild automation for the free Apple ID's 7-day resign limit

## Working style notes for whoever picks this up

- User wants full files resent (not diffs) when asked to "resend" something — established pattern after a partial-paste corrupted `Code.gs` once.
- Always visually verify UI changes in the iOS Simulator (screenshot) rather than trusting "BUILD SUCCEEDED" — user corrected this explicitly earlier in the project.
- Casual tone, short messages, comfortable with technical detail but appreciates plain-English explanations of *why*, not just *what*.
- Currently mid-lesson on the ML classifier — resume teaching, don't just build ahead.
