# `core/widgets`

Reusable, application-agnostic presentation primitives. They may be consumed by
more than one feature, but they must not know about jobs, customers, employees,
files or any other domain concept.

## Current component catalogue

| Component | Responsibility |
|---|---|
| `AppNavigationScaffold` / `AppPageBody` / `AppContentWidth` | Responsive app shell, safe scrolling and shared content width caps |
| `AppBottomNav` / `AppNavigationRail` | One role-aware destination model with phone and wide-screen renderings |
| `AppSurfacePanel` | White bordered surface with optional divider rhythm for related rows |
| `AppSectionHeader` | Section hierarchy on the open canvas |
| `AppDashboardHeader` / `AppStatGrid` / `AppStatTile` | Reusable dashboard hierarchy and numerical summaries |
| `AppStatusBadge` | Semantic, localized compact state labels |
| `AppSyncStatusBadge` | Sync-specific mapping built on the shared badge primitive |
| `AppLoadingStateView` / `AppEmptyStateView` / `AppErrorStateView` | Consistent asynchronous states, including retry affordance |
| `LanguageSwitcher` | Persisted locale control rendered with theme tokens |

## Rules

1. **No feature leakage.** Domain-aware widgets stay in
   `lib/features/<feature>/presentation/widgets/`.
2. **No business logic.** A core widget renders state supplied by its caller;
   it never calls Cubits, repositories, Supabase or Drift.
3. **No local visual system.** Resolve colours and typography through
   `Theme.of(context)`/`BuildContextX`, and use `core/theme` tokens for shape,
   spacing and dimensions.
4. **No fixed UI copy.** Labels, titles and messages are supplied by callers
   after localization. Components may shape typography, but never own a German
   or English string.
5. **Accessibility is part of the primitive.** Preserve semantics, visible
   focus/error states and touch targets for interactive controls.

The implementation policy and token values live in
[`../theme/README.md`](../theme/README.md).
