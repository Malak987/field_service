# Heimwerk Design System

The design system is intentionally code-first. Screens consume tokens from this
folder and shared primitives from `core/widgets`; they do not create their own
colours, radii, spacing scales or responsive thresholds.

## Brand and colour roles

The Heimwerk logo establishes the identity: a deep burgundy wordmark with a
warm gold service line. The interface uses this identity with a light, precise
field-service aesthetic rather than a default Material blue treatment.

| Role | Token | Value | Use |
|---|---|---:|---|
| Brand | `AppColors.primary` | `#7B1E28` | Primary actions, selection and key emphasis |
| Brand pressed | `AppColors.primaryDark` | `#5C151D` | Pressed states and strong accents |
| Accent | `AppColors.goldAccent` | `#C89F6A` | Small decorative or workflow accents; never a full CTA |
| Canvas | `AppColors.background` | `#F6F1E7` | App/page background |
| Surface | `AppColors.surface` | `#FFFFFF` | Cards, fields, dialogs and navigation |
| Muted surface | `AppColors.surfaceMuted` | `#FBF8F2` | Inset/read-only states |
| Border | `AppColors.border` | `#E5DDD2` | Normal hairlines and dividers |
| Primary text | `AppColors.textPrimary` | `#242424` | Headings, values and body content |
| Secondary text | `AppColors.textSecondary` | `#55504B` | Supporting text and hints |
| Success / warning / error / info | `AppColors.*` | semantic | Status foregrounds and their matching `*Surface` washes |

`AppTheme.light` maps these roles to Material's `ColorScheme`. There is no dark
theme in the current product, so no new dark treatment has been introduced.
Any future dark implementation must add a complete token mapping rather than
overriding individual screens.

## Type scale

`AppTextStyles` is the only typography source. The scale is tuned for German
copy, where labels are often long, and for one-handed field work:

- `headlineMedium` — 22/27.5, 700: screen greetings and page titles.
- `metric` / `headlineSmall` — 26/28.6, 700, tabular figures: dashboard
  counts and numerical summaries.
- `titleLarge` — 17/22.1, 700: app bar and section titles.
- `titleMedium` — 15.5/21.7, 600: card titles and important labels.
- `titleSmall` — 13.5/18.9, 700: eyebrow/section labels.
- `bodyLarge`, `bodyMedium`, `bodySmall` — 15, 14 and 12.5: body, supporting
  content and metadata.
- `buttonLabel`, `linkLabel`, `badgeLabel` — action and compact-status text.

Screens should consume `context.textStyles` so the Material theme remains the
single type mapping. Do not create a local `TextStyle` just to change a size or
weight.

## Space, shape and elevation

`AppSpacing` uses a fixed rhythm: `2, 4, 8, 12, 16, 20, 24, 32, 40`. The normal
screen gutter is 16 on compact phones and content blocks use 16 or 24 inside
surfaces. Sections separate with 32, not stacks of competing cards.

`AppRadius` is deliberately restrained: 10 for controls, 12 for panels and
cards, 16 for overlays, and a pill only for chips and status badges.

`AppElevation` makes the shadow rule explicit: cards and panels remain at zero
elevation with a warm hairline border; only floating actions and overlays may
lift above content. This keeps job information practical and avoids the
floating-card look of default Flutter applications.

## Component rules

- **Primary buttons** use the filled burgundy treatment; height is 52. The
  pressed state deepens to `primaryDark`; disabled controls preserve an obvious
  but muted state.
- **Secondary actions** use `OutlinedButton`; tertiary actions use
  `TextButton`. Toolbar actions are 44 minimum.
- **Inputs** are white, 1px bordered, 10px rounded and use a burgundy 1.6px
  focus ring. Error state is semantic red, including its helper copy.
- **Surfaces** use `AppSurfacePanel` for related rows and hairline dividers;
  use a card only when the group itself needs separation from the canvas.
- **Status badges** use `AppStatusBadge` with a semantic `AppStatusTone`, an
  icon when helpful, and a localized text label. Colour alone must never carry
  the state.
- **Loading, empty and error states** use `AppLoadingStateView`,
  `AppEmptyStateView` and `AppErrorStateView`. Errors retain retry behaviour;
  empty states never impersonate failures.
- **Navigation** is role-aware but visually consistent: `NavigationBar` on
  phones and `NavigationRail` at desktop widths, fed from the same destination
  model.

Copy belongs to the feature and must be obtained from `AppLocalizations`; shared
widgets accept labels from callers and never embed translated interface text.

## Responsive contract

`AppDimensions` owns all layout thresholds:

| Threshold | Behaviour |
|---:|---|
| `< 380` | Compact mobile gutters/control decisions |
| `>= 600` | Tablet layouts such as four-column metric grids may be used |
| `>= 900` | NavigationRail replaces the bottom navigation; a two-column/data-dense layout may be used |

`AppPageBody` centres content and caps regular reading/form content at 720px.
Data-dense management views opt into its 1120px wide cap. New screens must use
these existing values rather than declaring an arbitrary local breakpoint.

## Implementation boundary

Core primitives are presentation-only: no repositories, Cubits, Supabase,
Drift or feature/domain types. Feature widgets can map their domain state into
the generic primitives, keeping the architecture and existing job flows intact.
