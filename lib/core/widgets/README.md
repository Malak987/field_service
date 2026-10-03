# core/widgets

Truly reusable, application-agnostic widgets only.

Reserved for components that are used by **more than one feature** and that
carry no domain meaning, for example:

- `AppLoader` / `LoadingIndicator`
- `EmptyStateView`
- `ErrorRetryView`
- `AppSnackBar` helpers
- generic form fields and pickers built on top of `core/theme`

## Rules

1. **No feature may leak here.** A widget that knows about jobs, customers,
   employees or file uploads belongs to that feature
   (`lib/features/<feature>/presentation/widgets/`).
2. **No business logic.** Widgets render state that Cubits provide; they never
   call repositories, data sources, Supabase or Drift.
3. **No hardcoded colours or sizes.** Everything resolves through
   `core/theme` (`AppTheme` / `AppColors`) so light and dark mode stay correct.

Phase 3 deliberately ships this folder empty: widgets are added when the first
real screen needs them, so no placeholder component is created "just in case".
