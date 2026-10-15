# Heimwerk store release setup

> **Purpose:** owner-editable release checklist for Google Play and the Apple App Store.
>
> **Scope and safety:** this checklist was refreshed on 2026-10-14 from the copied local repository, reviewed privacy drafts, and available project files. It contains no signing material, passwords, API keys, or store URLs. Contact details below are owner-supplied draft inputs and do not confirm that a public inbox is monitored. Store submission and production Supabase changes are outside this update.

## 1. Current repository state

- Current branch: `main`; remote `origin` is configured. This update does not switch branches, stage, commit, push, or merge.
- The worktree already contains unrelated, pre-existing changes (including account deletion, Android configuration, and a deleted `lib.zip`). They are preserved and are not part of this update.
- Flutter app version from `pubspec.yaml`: `1.0.0+1`.
- Android display name: `Heimwerk`.
- iOS display name and bundle name: `Heimwerk`.
- Android namespace and application ID: `com.example.field_service`.
- iOS Runner bundle identifier: `com.example.fieldService`.
- iOS deployment target: `15.0`.
- Android `minSdk`, `compileSdk`, and `targetSdk` are delegated to Flutter. Static inspection of the configured Flutter SDK's Gradle extension reports defaults 24/36/36; no build was run, so this is source-level configuration, not a verified APK/AAB manifest.
- Android launcher mipmap assets are present. The iOS AppIcon asset set has its listed iPhone, iPad, and 1024×1024 marketing slots.

**Identifier decision:** the Android and iOS identifiers above intentionally remain unchanged in this phase. They look like template/example identifiers and must be explicitly confirmed by the account owner before a first production upload. Changing either identifier creates a different store application and must not be done casually.

## 2. Safe repository changes made in this phase

These changes implement existing application requirements; they do not change any backend, account, identifier, or store account.

1. Added `android.permission.INTERNET` to the **main** Android manifest. It was previously limited to the debug manifest even though the production app uses Supabase and synchronization.
2. Registered the existing `fieldservice` custom URL scheme in Android and iOS native configuration:
   - `fieldservice://auth-callback`
   - `fieldservice://reset-password`

   The scheme and hosts already existed in `lib/core/deep_linking/auth_deep_link_config.dart`; this phase makes the native platforms able to route those links into the app. These are custom-scheme deep links, not verified Android App Links or iOS Universal Links.
3. Android release signing is configured to use an ignored local `android/key.properties` file and does not fall back to a debug key. The file was checked without printing its values; required properties were present and its configured keystore path resolved to an existing file. Certificate identity and a signed release build were not verified.
4. Added this owner-editable checklist. This update corrects repository state, adds the data inventory below, and adds German iOS permission strings based on the existing English descriptions.
5. Added unpublished English/German draft pages under `store_pages_draft/` for the privacy policy and web account-deletion request. They preserve the supplied contact name Malak Ezat and proposed email malakdeveloper9876@gmail.com, with an explicit requirement to verify that the inbox is monitored. They are outside Flutter's `web/` build directory, remain local drafts, and must not be published or submitted as store URLs until completed, approved, hosted, and tested.

### Authentication redirect follow-up

Native registration alone is not sufficient for email confirmation or password recovery. The owner must verify that the production Supabase Auth redirect allow-list accepts the exact URLs above, and test both flows on physical Android and iOS devices. This is a production backend setting and was deliberately not changed here.

## 3. Android signing: local-only configuration

### Current state

- Before this phase, the Android `release` build type explicitly used the debug signing configuration. That is not acceptable for a Play upload.
- `android/key.properties` and its referenced keystore are present locally. Property values and keystore contents were not opened or printed.
- `android/.gitignore` already ignores `key.properties`, `**/*.keystore`, and `**/*.jks`.
- No signing key, alias, password, certificate, or provisioning material has been requested, created, read, moved, printed, or saved by this work.

### Owner-only setup required before a signed Android release

1. Use the owner's approved upload key and keep it outside Git and this shared workspace.
2. On the secure build machine, create `android/key.properties` locally. It must contain the following four property **names** with the owner's real local values:
   - `storeFile`
   - `storePassword`
   - `keyAlias`
   - `keyPassword`
3. Confirm the local keystore path in `storeFile` resolves from the Android app Gradle build.
4. Build a release App Bundle only in the owner's trusted environment and verify the signing certificate before upload.

The Gradle file will not fall back to the debug key. If `key.properties` exists but omits one of the required properties, Gradle stops with the missing property name and points to this document; no secret value is printed.

## 4. Apple signing and native privacy requirements

### Current state

- Runner is configured for automatic code signing.
- No `DEVELOPMENT_TEAM` was found in the checked-in Xcode project settings.
- No iOS entitlement file was found.
- `Info.plist` registers the existing `fieldservice` scheme and contains English `NSCameraUsageDescription` and `NSPhotoLibraryUsageDescription` strings.
- German equivalents are now provided in `ios/Runner/de.lproj/InfoPlist.strings`, registered as a German iOS localization in the Xcode project.
- `NSPhotoLibraryAddUsageDescription` was not added because the app does not currently declare a flow that writes images to the user's photo library.

### Owner decisions and edits required

Review and approve the user-facing purpose copy before store submission. English wording is in `ios/Runner/Info.plist`; German wording is in `ios/Runner/de.lproj/InfoPlist.strings`:

- `NSCameraUsageDescription` — required if users can capture photos using the camera.
- `NSPhotoLibraryUsageDescription` — required if users can select existing photos.
- `NSPhotoLibraryAddUsageDescription` — add only if the app writes images to the user's photo library.

The German text translates the existing English app behavior (taking before/after job photos and attaching existing photos). The owner should confirm that both versions accurately describe the production behavior.

The owner must also select the Apple Developer team, configure the correct App ID/capabilities/provisioning in Apple Developer/Xcode, archive on macOS, and validate the archive before App Store Connect upload. None of these account-side actions was performed.

## 5. Account creation and account deletion

### Current client behavior and backend status

- The app supports an authenticated two-step **account-deletion** flow in the account screen: preview first, then an explicit final confirmation.
- The checked-out repository still contains no `delete-account` Function source or deployable Supabase project configuration. The connected production project has an active `delete-account` Function (v1, JWT verification enabled); its deployed behavior was read-only inspected for this audit. This app integration has no local deployable substitute.
- The UI explains the account-deletion effect: the sign-in account/email is deleted while the employee record, work history, photos, and signatures remain until expiry. The current backend workflow clears the employee profile email and deactivates the employee account, but does not guarantee removal of employee name, employee code, phone number, or role; anonymization is not implemented or verified.
- No service-role key, administrative secret, user id, SQL, RLS, Storage operation, or local job/customer/employee/file deletion is present in the Flutter client.
- `supabase/admin_management_setup.sql` contains an administrator-controlled technician soft-delete concept. That is unrelated to this self-service workflow.

### `delete-account` Edge Function contract used by the client

The Supabase client supplies the current session JWT automatically. The mobile client never adds an Authorization header or privileged credential itself.

1. **Preview:** before the final confirmation, the client calls:

   ```dart
   supabase.functions.invoke('delete-account', body: {'dry_run': true})
   ```

   A 2xx result is displayed as a preview; no account or application data is changed by the client. If the Function returns an optional string `message`/`summary` or retention detail, the app also displays it as server information without requiring a response schema.
2. **Confirmation:** only after the user reviews that preview and explicitly confirms, the client calls:

   ```dart
   supabase.functions.invoke('delete-account', body: {'confirm_delete': true})
   ```

   Only a 2xx response is a deletion success. The app then clears the device's local Supabase session and in-memory account state with local-only sign-out scope, and routes to the sign-in screen.
3. **Required error semantics:**
   - `401`: the app explains that the session is invalid, clears the invalid local session, and routes to sign-in; it is not treated as a deletion success.
   - `409` with `last_active_admin` in the Function error details: the app keeps the session open and explains that another active administrator must be added first.
   - any other transport, Function, or non-2xx error: the app shows a failure, keeps the account page/session open, and does not claim deletion.
4. **Server responsibilities:** the Function must validate the JWT and derive the caller from it, delete only the authenticated caller's sign-in account/email when `confirm_delete` is true, and preserve the employee/work/file history for the owner-approved retention period. Any privileged credential remains only in the Edge Function's server-side secrets.

No real account deletion was invoked or tested from this workspace.

## 6. Data inventory and 12-month job retention

This is a technical inventory for completing the store privacy forms; it is not a privacy policy or legal determination. The app repository shows the following data categories and relationships:

| Data | Where it appears | Product purpose / relationship | Retention understanding |
| --- | --- | --- | --- |
| Sign-in email and account identity | Supabase Auth; app authentication flow | Sign-in and account recovery | The deployed `delete-account` Function was read-only inspected: it deletes the authenticated Auth user after explicit confirmation. Auth-side log/backup retention was not inspected. |
| Employee records, including technician/admin profiles | `public.employees` | Staff identity, role, active status; jobs refer to assigned employees | Retained when a job expires. Account deletion should not remove this record if the business wants work history preserved. |
| Customer records and contact/address fields | `public.customers` | Customer details referenced by jobs | Retained when a job expires. Confirm exact collected fields and any export/sharing outside Supabase. |
| Job/work records | `public.jobs`; the app also stores job file metadata and offline operations locally | Customer, assigned employee, work description, status and job timestamps | Production trigger sets `expires_at = created_at + 1 year`. The purge Function selects expired jobs and deletes at most 100 per run. |
| Photos, signatures, and job documents | `public.job_files` plus the private Supabase Storage bucket `job-files`; object paths are job-scoped | Before/after evidence, customer signature, and any attached document | Production Function v2 recursively removes Storage objects under `jobs/{job_id}/` before deleting each job. If Storage cleanup fails, it leaves the database job for retry. `job_files` rows cascade with the job. |
| Job activity events | `public.job_events` | Audit trail for job creation/start/completion and photo/signature events | Production foreign key cascades these rows with the job. Employee profiles are referenced with `ON DELETE SET NULL`, so employee records are retained. |

**Production check performed 2026-10-14:** active Edge Function `purge-expired-job-data` v2 is scheduled daily at 03:00 UTC. The latest recorded cron run succeeded at 03:00 UTC on 2026-10-14; the latest three asynchronous HTTP responses in the inspected window were HTTP 200, with the latest aligned to that run. Structured Function logs could not be retrieved, so this is scheduler/HTTP evidence rather than proof of every internal step. A read-only eligibility count found 0 expired jobs at check time; no account, row, or Storage object was deleted during this audit. The cron request uses a Vault lookup for its secret header; the secret value was not read. Each purge invocation handles at most 100 jobs; a larger backlog drains over multiple daily runs. `customers` uses `ON DELETE RESTRICT`, and the purge code deletes jobs only; it does not delete employee, customer, or admin rows.

**Remaining retention gap:** local job-file metadata and original photo/signature bytes remain after successful uploads: the upload handler marks them synced, but never invokes the available local delete-after-upload method. The sync queue retains successful payload rows and failed/pending work has no expiry-pruning implementation. Local customer cache data also remains. Additionally, the backend upload and registration checks inspected do not enforce `jobs.expires_at`; an offline/stale client can attempt a late upload until job deletion blocks it. No local cleanup or stale-operation expiry was implemented here because deleting queued work could destroy unsynced business records. Decide how pending work is reconciled, then implement and verify device cleanup and server-side expiry guards.

**Retention scope:** the 12-month period is the target for each job, measured from job creation. Production checks verified the configured daily server-side cleanup of eligible job rows and job-scoped objects in Supabase Storage, with associated `job_files` and `job_events` removed through database cascade. It does not cover local device files, queued offline operations/uploads, the separate historical database snapshot, or provider backups. Local cleanup is not implemented in this checkout, and backup retention/deletion behavior remains unconfirmed. Do not describe every copy as covered by the server-side 12-month schedule.

**Draft documents:** [privacy-policy.html](store_pages_draft/privacy-policy.html) and [account-deletion.html](store_pages_draft/account-deletion.html) are bilingual English/German drafts based on checked app/backend behavior and the reviewed owner-supplied draft contact (Malak Ezat, malakdeveloper9876@gmail.com). They are not hosted, published, or legal approval. The deletion page is not yet a working public request route: monitoring of the proposed inbox, identity verification, handling, and response deadlines have not been confirmed. Do not use these files as store URLs until the gaps below are resolved, the pages are hosted, and links and request handling are tested.

### Privacy and deletion gaps before publication

- **Legal controller identity:** confirm who legally determines processing purposes and means, the controller's legal name/status, and postal address. The supplied contact name alone does not establish the legal controller.
- **Support/privacy inbox:** verify that `malakdeveloper9876@gmail.com` is controlled by the responsible operator, monitored, and suitable for public privacy and deletion requests. Define identity verification, request handling, confirmation, and response deadlines; test the flow.
- **Employee data on account deletion:** current behavior clears the employee profile email and deactivates the linked employee account, but retains the employee row and may retain name, employee code, phone number, and role. Anonymization/de-identification is not implemented or verified. Decide which fields should be removed or retained, the lawful reason and period, and implement/verify any approved change before describing it as done.
- **Store account-deletion requirements:** Apple requires in-app initiation and deletion of the account and associated data unless there is an actual legal retention requirement. The current workflow preserves employee identifiers and work attribution without a verified legal basis/retention exception. Resolve this policy and implementation mismatch before an App Store submission; do not label the remaining fields legally required without evidence. Google Play also requires an external web request path for account/data deletion when users cannot complete deletion in-app; the draft URL is not hosted or operational.
- **12-month retention scope:** server-side job and Storage cleanup is verified. App-side expiry cleanup for device files/caches and queued offline operations/uploads is not implemented or verified. Supabase/provider backup retention and deletion behavior are unconfirmed. Resolve these before claiming all copies are automatically deleted after 12 months.
- **Legal retention exceptions:** identify only actual legal or other documented exceptions, affected data categories, reasons, and retention periods. No generic exception has been approved here.
- **Remaining policy facts:** confirm exact data fields, permissions, diagnostics/analytics, processors/subprocessors, legal bases and controller/processor roles, applicable rights/complaint authority, intended age group, and international transfers or backup details.
- **Publication gate:** complete and review the English and German text, validate internal links, make the public deletion request path usable without signing in, test it, and obtain explicit owner/legal approval. These local drafts are not published and this update is not legal approval.

## 7. Audit findings and proposed remediation (not applied to production)

### High-priority production ACL issue

The live `public.admin_action_log` table ACL grants `TRUNCATE` to both `anon` and `authenticated`. RLS does not restrict `TRUNCATE`, so an unauthenticated caller can erase the administrator audit log. No command was run against production. The review-only proposal is [admin_action_log_acl_remediation.sql](supabase/proposals/admin_action_log_acl_remediation.sql). It revokes table privileges from both roles, then restores only authenticated `SELECT` (still subject to the existing admin-only RLS policy); it includes post-change privilege checks. This requires explicit owner approval and a controlled production change.

Other review findings: the private `job-files` bucket has no configured upload size or MIME allow-list; the last-active-admin check in account deletion is not serialized against concurrent requests; account deletion deactivates the employee before deleting the Auth user, so a later Auth failure leaves a partial state; and the account-deletion impact preview may undercount file rows for employees with more than the REST default page size of assigned jobs. The deletion Function only clears employee email and deactivates the profile; it keeps employee name, code, phone, and role.

The purge Function deletes at most 100 expired jobs per run and correctly leaves a job row for retry if Storage removal fails. Current upload/registration paths do not check expiry. A persisted `backup_20261011` database snapshot schema also exists; its tables are inaccessible to `anon`/`authenticated` in inspected grants, but its retention/disposal policy is unknown. Do not delete it before deciding legal and operational retention. Database migrations are recorded in production but no matching local migration history/configuration is present in this repository, so production state is not reproducible from this checkout.

### Phase 1 follow-up: offline uploads and employee-field decision

#### Existing Offline-First data flow observed

1. **Local writes first where supported:** customer create/update/delete writes to Drift and then enqueues a durable operation. Technician job creation enqueues a single operation with stable job/customer IDs and a draft payload; when online it may also call the idempotent server RPC immediately. Starting a job and saving work description enqueue job updates. Job completion intentionally requires a server response and is unavailable offline.
2. **Photos and signatures:** `LocalFileStorage` copies captured/picked bytes into app-owned files, inserts a local `job_files` row, and enqueues one upload operation with a stable file ID and job ID. This path itself does not require network access.
3. **Queue persistence/order:** Drift `sync_queue` stores JSON payloads, status, attempt count, last error, creation time, and optional `depends_on`. The manager processes pending operations oldest-first while respecting dependencies; conditional claims prevent two concurrent runs from pushing the same row.
4. **Startup and connectivity:** `SyncManager.start()` restores `inProgress` operations to `pending`, watches connectivity, and starts a sync pass when online. Losing connectivity releases the claimed operation to `pending`; no row is cleared.
5. **File push:** the file handler reads the local bytes, uploads to the deterministic Storage path using upsert, calls `register_job_file`, then marks the local file row synced. The stable IDs and server RPC's idempotency protect retries from creating duplicate logical records/events.
6. **Errors and retries:** transient and server failures are mapped to safe text and persisted as `failed`; a failed row is not selected by ordinary pending processing. An explicit retry requeues all failed operations. Timeouts/network failures are not proof that the server rejected or expired the job. Queue entries are not automatically removed after success either; their status becomes `synced`.
7. **Local file lifetime:** local bytes and metadata are not automatically deleted after upload; a guarded `deleteAfterConfirmedUpload` helper exists but has no caller. No local expiry purge for files, queue rows, or customer copies was found. Remote daily purge does not clean these local copies.
8. **Non-atomic local boundaries:** file bytes, local metadata, and queue insertion are sequential writes, not one database/filesystem transaction. A process failure between steps can leave an orphan local file or metadata without its queue operation. No repair was attempted because migration/reconciliation logic could alter existing user data.

These are source-inspection findings, not runtime test results. The sync queue's existing retry contract and payload retention are intentionally preserved.

**Offline expiry guard not implemented:** `JobFileSyncHandler` uploads file bytes to Storage first and only then calls `register_job_file`. The live `can_upload_job_object` helper and `register_job_file` RPC check assignment, active employee, job state, and path, but neither checks `jobs.expires_at`. A job that has passed expiry but is still present and `in_progress` may therefore accept a stale upload. After purge removes the job, the upload is rejected by the Storage policy / registration reports not found. The manager records thrown errors as `failed`; those rows and payloads remain locally. Failed rows are not retried continuously in the same run, but `retryFailedOperations()` requeues all failures, and crash recovery requeues in-flight rows. There is no terminal “expired” state or per-operation retry suppression.

I made no queue or upload change: the device cannot authoritatively decide whether a job is expired from a locally cached timestamp, and a client preflight alone has a time-of-check/time-of-use gap before Storage upload. A safe complete fix requires server enforcement using the database clock in **both** the Storage upload policy/helper and `register_job_file`, plus a server-authoritative eligibility result before the bytes are sent if the product requires avoiding even a rejected upload attempt. Expired/not-found outcomes need a stable machine-readable classification so the client can preserve the queue/file as a visible blocked item, not repeatedly auto-retry or silently discard it. No endpoint, policy, schema, or deployed Function was added or changed in this phase. Until the owner approves that server contract, retain the offline payloads and do not claim device copies expire automatically.

**Employee deletion field proposal — decision required, not a legal conclusion:** production `employees` currently has `id`, `auth_user_id`, `employee_code`, `name`, `phone`, `email`, `role`, `is_active`, `created_at`, `updated_at`, `account_status`, `blocked_at`, `deleted_at`, `status_changed_at`, and `status_changed_by`. The current self-deletion workflow clears `email`, deactivates the row, and deletes the linked Auth user; it does not anonymize the other fields.

| Field | Current effect / relationship | Candidate owner decision | Operational consequence |
| --- | --- | --- | --- |
| `id` | Stable employee key used by jobs, job events, customer creator attribution, and audit actors | Retain as an opaque historical key if preserving work attribution; deletion would require resolving references | Retention keeps joins intact; replacing/deleting may break or erase attribution, and customer creator FK currently restricts employee deletion |
| `auth_user_id` | Link to Supabase Auth; becomes null when Auth user is deleted | Clear (current FK behavior) | Prevents the deleted login from remaining linked; does not anonymize the employee row |
| `email` | Contact/login value copied into employee profile | Clear (current workflow) | Removes this profile contact field, subject to Auth/provider logs outside this row |
| `name` | Identifies the employee in profiles and historical job displays | Retain only for an approved purpose/period, or replace with a neutral label | Replacing it preserves job grouping but loses readable attribution; column is currently NOT NULL |
| `employee_code` | Staff identifier; currently NOT NULL | Retain only if operationally needed, or replace with a unique non-identifying tombstone value | Nulling requires schema change; replacement may affect reports and uniqueness/reuse policy |
| `phone` | Optional staff contact field | Clear unless an approved documented need requires retention | Removes direct contact from the employee row; may affect staff follow-up |
| `role` | Authorization/business category; currently NOT NULL | Decide whether historical role is needed; if removed, replace with a non-authorizing historical category only after role/RLS impact review | Role affects admin/technician interpretation; `is_active=false` is also enforced, but historical reporting may change |
| `is_active`, `account_status` | Current account availability/status | Keep inactive/deleted state | Prevents sign-in-linked staff access and records the workflow outcome |
| `created_at`, `updated_at`, `blocked_at`, `deleted_at`, `status_changed_at` | Lifecycle timestamps | Keep only approved audit/lifecycle timestamps | Supports operational history; can still be linkable metadata |
| `status_changed_by` | References the employee/admin who changed status | Retain for audit attribution or clear under an approved audit policy | Clearing loses actor attribution; `admin_action_log` has separate audit references |

Customers, customer contact details, jobs, photos, signatures, and job history are outside this field proposal and remain unchanged. Decide each retention/anonymization field and its period before changing the account-deletion behavior; any legal-retention claim needs owner/legal evidence.

### Cache isolation review

`JobFilesRemoteDataSourceImpl` scopes in-memory image cache keys by current user ID, skips caching without a signed-in user, and rejects a completed download if the user changed while it was in flight, so those bytes are not handed to the new session's caller. This is an existing local source change from the preceding phase, reviewed here and left intact. Cache failure paths do not store bytes because a failed download throws before the cache write. The small in-memory cache remains per data-source instance; no tests were run in this phase.

### Retention lifecycle matrix

| Data copy | Observed behavior | 12-month automatic cleanup status | Safe next action |
| --- | --- | --- | --- |
| Job rows (`jobs`) | Expiry timestamp plus daily purge; child rows cascade | Verified live configuration; no expired jobs at audit time | Add expiry immutability/guard checks; retain daily monitoring |
| Job event rows (`job_events`) | Cascade on job deletion | Covered by server job deletion | Verify cascade after approved non-production test |
| File metadata (`job_files`) | Cascades after job deletion | Covered server-side | Keep job/file cascade aligned |
| Supabase Storage photos/signatures | Job-prefix recursive removal before DB delete | Covered by server purge; HTTP/cron evidence only | Add MIME/size limits and expiry upload guard |
| Local uploaded photos/signatures | Local bytes and metadata remain after successful upload | Not implemented | Decide safe local purge after confirming remote upload and ownership |
| Local pending/failed sync queue | Operation payload remains; can include customer/job data | Not implemented | Preserve unsynced work; define reconciliation, then expire safely |
| In-memory photo cache | Previously path-only; now cache lookup is scoped by current user ID | Cross-account local fix prepared in source; not tested | Run focused test/device account-switch validation later |
| Local customer mirror | Customer details retained on device | No automatic deletion | Set product/legal policy; do not delete as job expiry |
| Employees, customers, admins | Not deleted by job purge | Excluded by design | Retain separately under approved business/legal policy |
| Auth account on self-delete | Auth user deleted; employee row deactivated/email cleared | Immediate account workflow, separate from retention | Fix transaction/race behavior before relying on it operationally |
| Historical DB snapshot / provider backups | Private snapshot exists; provider backup details unknown | Unknown | Owner decides snapshot retention and obtains provider backup terms |

No expiry, local data deletion, SQL grant, Function, database policy, backup, or production setting was changed in this audit.

## 7. Target SDK status and Google Play decision

Google Play's official target API policy states that, from **2026-08-31**, new mobile apps and updates must target **Android 16 / API level 36 or higher**. Reference: [Google Play target API requirements](https://support.google.com/googleplay/android-developer/answer/11926878?hl=en-NG). Apple requires in-app account deletion and associated-data deletion except information actually required to be retained by law: [Apple account deletion guideline](https://developer.apple.com/help/app-review/guideline-reference/5-1-1-account-deletion/). Google Play also requires a functional web link/path for deletion requests when the app supports account creation: [Google Play account deletion requirements](https://support.google.com/googleplay/android-developer/answer/13327111?hl=en).

| Item | Current value / decision |
| --- | --- |
| Required Play target at the time of this checklist | API 36 or higher for new apps and updates |
| Project configuration | `targetSdk = flutter.targetSdkVersion` in `android/app/build.gradle.kts` |
| Flutter SDK source default | **36** (static source inspection of configured SDK Gradle extension) |
| Verified packaged target SDK | **Not verified**; no APK/AAB was built or inspected. |
| Why | Flutter CLI/build was not run, so plugin overrides or final manifest merging were not observed. |
| Change in this phase | None. The target SDK was deliberately not changed. |

A target-SDK update can change Android compatibility behavior and may require testing permissions, photo capture/selection, notifications if introduced, background/sync behavior, authentication redirects, and offline recovery. Before any target-SDK edit, the owner must approve it after the effective Flutter value is established and a test plan is agreed.

## 8. Required owner inputs: fill-in checklist

Do not replace the blanks with guesses. Keep production URLs, contacts, and legal statements under the owner's control.

### Store identity and contacts

- [ ] Confirm whether the current Android application ID should remain `com.example.field_service`: `____________________________`
- [ ] Confirm whether the current iOS bundle ID should remain `com.example.fieldService`: `____________________________`
- [ ] Confirm public app name: `____________________________`
- [ ] Confirm legal controller/developer identity and status: `____________________________`
- [ ] Confirm controller postal address: `____________________________`
- [ ] Verify the supplied support/privacy email `malakdeveloper9876@gmail.com` is controlled by the responsible operator and monitored: `____________________________`
- [ ] Define and test deletion-request identity verification, handling, confirmation, and response deadlines: `____________________________`
- [ ] Public support website: `____________________________`
- [ ] Privacy-policy URL: `____________________________`
- [ ] Account-deletion request URL/process: `____________________________`
- [ ] Privacy contact / data-protection contact: `____________________________`
- [ ] Document actual legal retention exceptions, data categories, reasons, and periods (or confirm none): `____________________________`
- [ ] Confirm local-device cache/file and queued-operation cleanup behavior: `____________________________`
- [ ] Confirm provider backup retention/deletion behavior: `____________________________`

### Google Play listing and compliance

- [ ] Short description (owner-approved): `____________________________`
- [ ] Full description (owner-approved): `____________________________`
- [ ] App category and tags: `____________________________`
- [ ] Countries/regions, pricing, and distribution choices: `____________________________`
- [ ] 512×512 Play icon reviewed and approved: `____________________________`
- [ ] Feature graphic, phone/tablet screenshots, and any video are owner-approved and match the current product: `____________________________`
- [ ] Content rating questionnaire completed truthfully: `____________________________`
- [ ] Data Safety answers completed from the actual data flows, retention, sharing, security practices, and account-deletion policy: `____________________________`
- [ ] Advertising ID declaration completed from the actual app/dependencies: `____________________________`
- [ ] Target SDK is confirmed as API 36+ after resolving the installed Flutter SDK: `____________________________`
- [ ] Play App Signing / upload-key ownership and recovery process recorded outside this repository: `____________________________`

### App Store Connect listing and compliance

- [ ] Apple Developer team and App Store Connect app record selected: `____________________________`
- [ ] App name, subtitle, description, keywords, category, and support/marketing URLs are owner-approved: `____________________________`
- [ ] 1024×1024 App Store icon reviewed against current Apple requirements: `____________________________`
- [ ] Required iPhone/iPad screenshots and app preview media are owner-approved and show actual behavior: `____________________________`
- [ ] Age rating and content declarations completed truthfully: `____________________________`
- [ ] App Privacy questionnaire completed from verified data collection, linkage, tracking, sharing, and retention practices: `____________________________`
- [ ] Camera/photo-library purpose copy is approved and localized before it is added: `____________________________`
- [ ] Export compliance, encryption, tax/banking, trader/contact, and regional distribution questions completed truthfully where applicable: `____________________________`
- [ ] App Review contact and review notes include a valid test path only if the owner authorizes one: `____________________________`

### Product and backend verification

- [ ] Supabase production project/environment is selected and verified by the owner; no service-role secret is in the mobile app: `____________________________`
- [ ] Auth redirect allow-list includes `fieldservice://auth-callback` and `fieldservice://reset-password` if those flows are intended for production: `____________________________`
- [ ] Sign-up, email confirmation, password reset, and password update are tested on real Android and iOS devices: `____________________________`
- [ ] Photo capture, photo selection, upload, retry/sync, and signature behavior are tested on real devices: `____________________________`
- [ ] Account deletion policy, in-app flow, public request URL, and server-side implementation are approved before claiming a deletion option: `____________________________`
- [ ] Privacy policy and disclosures have been reviewed by the owner's appropriate legal/privacy decision-maker: `____________________________`

## 9. Validation performed in this environment

| Check | Actual result |
| --- | --- |
| Branch / Git | Current branch is `main`; `origin` is configured. Existing worktree modifications were preserved. No commit, push, or merge was made. |
| Flutter SDK target default | Static inspection of configured SDK source reports `targetSdkVersion=36`; no CLI/build/package manifest verification was performed. |
| Configured local Flutter SDK | `android/local.properties` is present; source-level Flutter default target is 36. Effective packaged manifest remains unverified. |
| Dart executable | Present inside the Flutter SDK, but not used. |
| Android Gradle wrapper / Gradle command | `android/gradlew` exists; Gradle build was not run. No standalone Gradle command was available on `PATH`. |
| Android release signing | Required local property names were present and configured keystore path resolved; values were not read. Certificate identity and signed output were not verified. |
| Java | Not rechecked in this copy. The project declares Java 17 source/target compatibility. |
| Xcode | `xcodebuild` was not available in this Linux environment. |
| `flutter pub get` | Not run, as requested. |
| `flutter analyze` | Not run, as requested. |
| Flutter tests | Not run, as requested. |
| Android app bundle/APK build | Not run: Flutter/Gradle tooling and a signed local release configuration are unavailable. |
| iOS archive/build | Not run: Xcode is unavailable and iOS signing is not configured. |

No signed release build is claimed.

## 10. Before the next release attempt

1. Use a clean, trusted macOS/Android build environment with a compatible Flutter SDK, Java 17 for Android, Android SDK, Xcode for iOS, and the owner's local signing setup.
2. Resolve and record the actual Flutter-provided target SDK; obtain approval before changing it if it is below the then-current Play requirement.
3. Run `flutter pub get`, `flutter analyze`, the relevant automated tests, and device smoke tests.
4. Build an Android **unsigned** release only for preliminary build validation if signing is unavailable; do not upload it. Build a signed App Bundle only in the owner's secure setup.
5. Archive and validate the iOS app in Xcode using the owner's Apple team and provisioning.
6. Complete every applicable owner checklist item with verified production information.
7. Review the final Git diff separately from the pre-existing worktree changes before any owner-controlled commit or release.
