---
name: Momentum
description: A private iPhone execution system for fitness, nutrition, and personal care.
colors:
  brand-pulse: "oklch(0.620 0.200 355)"
  brand-pulse-dark-appearance: "oklch(0.720 0.180 355)"
  brand-pulse-deep: "oklch(0.500 0.170 355)"
  brand-pulse-wash: "oklch(0.940 0.035 355)"
  data-cyan: "oklch(0.820 0.105 220)"
  light-background: "oklch(1.000 0.000 0)"
  light-surface: "oklch(0.970 0.000 0)"
  light-ink: "oklch(0.160 0.008 355)"
  light-muted: "oklch(0.450 0.010 355)"
  dark-background: "oklch(0.100 0.000 0)"
  dark-surface: "oklch(0.160 0.008 355)"
  dark-ink: "oklch(0.960 0.000 0)"
  dark-muted: "oklch(0.740 0.010 355)"
typography:
  display:
    fontFamily: "SF Pro Display, system-ui, sans-serif"
    fontSize: "Dynamic Type: largeTitle"
    fontWeight: 700
    lineHeight: 1.08
    letterSpacing: "normal"
  headline:
    fontFamily: "SF Pro Text, system-ui, sans-serif"
    fontSize: "Dynamic Type: headline"
    fontWeight: 600
    lineHeight: 1.2
    letterSpacing: "normal"
  body:
    fontFamily: "SF Pro Text, system-ui, sans-serif"
    fontSize: "Dynamic Type: body"
    fontWeight: 400
    lineHeight: 1.35
    letterSpacing: "normal"
  label:
    fontFamily: "SF Pro Text, system-ui, sans-serif"
    fontSize: "Dynamic Type: subheadline"
    fontWeight: 600
    lineHeight: 1.2
    letterSpacing: "normal"
rounded:
  control: "10pt"
  surface: "14pt"
  prominent: "16pt"
spacing:
  xxs: "4pt"
  xs: "8pt"
  sm: "12pt"
  md: "16pt"
  lg: "24pt"
  xl: "32pt"
components:
  button-primary:
    backgroundColor: "{colors.brand-pulse}"
    textColor: "{colors.light-background}"
    typography: "{typography.headline}"
    rounded: "{rounded.control}"
    padding: "14pt 20pt"
    height: "50pt"
  button-secondary:
    backgroundColor: "{colors.light-surface}"
    textColor: "{colors.brand-pulse-deep}"
    typography: "{typography.headline}"
    rounded: "{rounded.control}"
    padding: "14pt 20pt"
    height: "50pt"
  activity-surface:
    backgroundColor: "{colors.light-surface}"
    textColor: "{colors.light-ink}"
    typography: "{typography.body}"
    rounded: "{rounded.surface}"
    padding: "16pt"
---

# Design System: Momentum

## Overview

**Creative North Star: “The Red Thread”**

Momentum is one continuous line of promises kept: a workout completed, a meal recorded, a care routine handled, then the next right action. The visual system makes that continuity tangible through one rare pulse-red accent, chronological structure, and calm evidence of accumulated effort. It does not decorate discipline; it reveals it.

The physical scene is specific: one person checks Momentum one-handed under harsh gym lighting between exercises, then later in a dim bathroom at 22:00 while tired and ready to finish the day. That demands instant hierarchy, generous targets, true light and dark appearances, and controls that remain obvious without close inspection.

Momentum uses standard iOS navigation and controls. iOS 26 Liquid Glass belongs to the system tab bar, toolbars, sheets, and a single prominent action when useful; logged content remains opaque and highly legible. Brand expression comes from the pulse tint, restrained typography, heatmap rhythm, crisp status language, and purposeful haptics—not a custom app shell.

**Key Characteristics:**

- Native, immediate, and one-handed
- Dense enough for the gym, calm enough for evening care
- Restrained color with one unmistakable pulse
- Honest statuses and nonjudgmental copy
- Flat content hierarchy with glass reserved for controls
- Accessible in bright light, darkness, large type, and grayscale

## Colors

The palette is neutral architecture with a vivid red-magenta pulse and a cool cyan reserved for secondary chart comparison. System semantic colors remain authoritative for success, warning, error, and informational states.

### Primary

- **Momentum Pulse:** the canonical interactive tint and selected-state color. Use the dark-appearance variant on dark backgrounds and the deep variant for text links on light backgrounds.
- **Momentum Wash:** a quiet selected-row or milestone background; it never carries low-contrast body text.

### Secondary

- **Data Cyan:** a chart-comparison color only. It is not a second action color and never competes with Momentum Pulse in navigation.

### Neutral

- **Light Background / Dark Background:** true neutral foundations for bright-gym and dim-evening use.
- **Light Surface / Dark Surface:** one step of tonal separation for grouped content, never a stack of nested panels.
- **Light Ink / Dark Ink:** primary content with at least 7:1 intended contrast against its paired background.
- **Light Muted / Dark Muted:** secondary labels; never use muted color for essential instructions or placeholder-only labels.

Implementation uses named Color assets with light/dark variants and SwiftUI semantic colors (`primary`, `secondary`, `systemBackground`, `secondarySystemBackground`, `separator`) wherever brand identity is not required. Do not paste OKLCH values throughout Views.

**The Ten Percent Rule.** Momentum Pulse occupies no more than roughly 10% of a normal screen. Its rarity gives it authority.

**The Meaning Rule.** Pulse means action, selection, or earned emphasis. System green means complete, orange means warning/overdue, and red means destructive/error. Never rely on hue alone; pair every state with text or an SF Symbol.

**The Heatmap Rule.** Heatmap intensity uses a five-step tonal ramp derived from Momentum Pulse, but zero/no-obligation is visually distinct from zero-completion through outline and accessibility labels.

## Typography

**Display Font:** SF Pro Display with the system fallback
**Body Font:** SF Pro Text with the system fallback
**Label/Mono Font:** SF Pro Text; use monospaced digits only for changing numeric values

**Character:** One native family creates confidence and removes ornamental decisions. Weight, Dynamic Type role, spacing, and alignment—not a novelty typeface—establish hierarchy.

### Hierarchy

- **Display** (bold, `largeTitle`): top-level navigation titles and rare milestone counts.
- **Headline** (semibold, `headline`): Due Workout, routine names, exercise names, and primary actions.
- **Title** (semibold, `title3`): section-level detail headings and sheet titles.
- **Body** (regular, `body`): instructions, notes, and explanatory copy; keep prose under roughly 70 characters per line where layout allows.
- **Label** (semibold, `subheadline`): field labels, compact status labels, and totals.
- **Supporting** (regular, `footnote`): timestamps and secondary metadata; never below the system caption floor.

Weights, reps, calories, protein, streak counts, and chart axes use `.monospacedDigit()` while staying in their semantic text style. Never hard-code point sizes.

**The Read-It-Tired Rule.** If a label only works when the user is fully attentive, it is too subtle. Essential instructions use Body or stronger, never Caption plus low contrast.

**The Sentence-Case Rule.** Buttons, statuses, and headings use sentence case. Uppercase tracking is prohibited.

## Elevation

Content is flat by default. Depth comes from system background hierarchy, separators, navigation transitions, sheets, and the iOS 26 tab/toolbar material. No custom drop shadow is applied to ordinary rows, activity surfaces, chart containers, or buttons.

Liquid Glass is interactive only on interactive elements. When multiple custom glass actions appear together, place them in one `GlassEffectContainer`; otherwise use native button and toolbar styles. Apply glass after layout and appearance modifiers. Under Reduce Transparency, replace custom glass with an opaque secondary system background and clear separator.

**The Content Stays Solid Rule.** Workout data, nutrition values, care instructions, and history never sit on decorative glass. Glass floats controls above content; it does not become the content.

**The One Prominent Action Rule.** A screen may have one glass-prominent or filled primary action. Secondary actions use native bordered, plain, menu, swipe, or toolbar treatments.

## Components

### Navigation

- Use native `TabView` with Today, History, Plans, and Progress.
- Each tab uses its own `NavigationStack` and large top-level title.
- Use SF Symbols only: `checklist`, `calendar`, `slider.horizontal.3`, and `chart.xyaxis.line` are starting points, subject to final symbol availability and visual testing.
- Settings is a standard toolbar item, not a fifth tab.
- Do not customize the system back button or edge-swipe behavior.

### Buttons

- **Primary:** one full-width or bottom-safe-area action, 50-point visual height with at least a 44-point target. Use `.glassProminent` on iOS 26 when it floats above scrolling content; use the brand-filled style inside opaque forms.
- **Secondary:** native bordered or plain treatment using brand-deep text in light appearance and brand-pulse-dark in dark appearance.
- **Destructive:** system destructive role, never the brand tint.
- **State:** disabled controls reduce prominence but retain legible labels; saving uses an inline progress indicator without changing button width.
- Use direct verbs: Start workout, Finish workout, Log food, Finish logging today.

### Today activity rows

- Use a chronological list with separators and generous 16-point horizontal insets.
- A compact leading SF Symbol communicates category; title and due/status text carry meaning independently.
- Completion uses a native check control with a short state transition and haptic.
- Expand tasks inline or push to a focused detail; never put a card inside an activity card.

### Due Workout surface

- This is the one content surface allowed stronger prominence on Today.
- Show workout name, one-line focus, due/overdue status, exercise count, and Start/Resume.
- Recovery uses the same footprint with quieter hierarchy, next eligible date, and Start Early as secondary.
- Do not show a giant streak, calorie, or completion percentage above the task.

### Nutrition progress

- Two aligned rows: Calories and Protein.
- Use a compact horizontal range/threshold visualization with textual totals.
- Calories show the green range; protein shows the minimum threshold.
- Log Food is visible without scrolling on ordinary Today states.
- Never use a moral label such as good, bad, cheat, or failed.

### Workout Session

- Use an immersive full-screen flow with an inline navigation title and persistent Finish Workout action in a safe-area inset.
- Exercises form clear sections, not nested cards.
- Each set row exposes set number, kg, reps, RIR, and completion in a stable order.
- Numeric fields use decimal/number keyboards and monospaced digits.
- Previous values sit directly below or beside the editable row at secondary emphasis.
- At accessibility text sizes, set rows reflow vertically rather than horizontally scrolling.

### Food Entry sheet

- Use a medium/large native sheet with Name, Calories, Protein, and Serving multiplier.
- Recent and Favorite choices appear above the form as a native searchable/list surface, not a chip cloud.
- Keep Save in the navigation toolbar and preserve the keyboard’s Next/Done flow.
- Validation appears inline next to the field; never discard a draft on save failure.

### Care Routine

- Present the routine title, due time, then vertically ordered checkable tasks.
- Conditional cleanse paths use a segmented control or two clearly labeled rows; selecting one fulfills the conditional group.
- Wait guidance uses secondary text beneath the related task, not a timer affordance.
- Completing from a notification is reversible from Today and History.

### Heatmap

- Seven rows by week columns, using 11–13-point cells with 3-point gaps and slightly rounded 3-point corners.
- Default window is 16 weeks; older weeks scroll horizontally.
- Selection opens a compact day summary rather than a tooltip that requires hover.
- VoiceOver groups by week and announces date, score, and completed/due counts.

### Charts

- Use Swift Charts with direct axis labels, target RuleMarks, and at most two emphasized series.
- Charts sit on the screen background or one tonal surface; no decorative plot-area gradients.
- Always pair a chart with a one-sentence textual summary.

### Forms and settings

- Use native `Form`, Sections, toggles, date pickers, menus, steppers, and destructive roles.
- Group by task rather than implementation subsystem.
- Footer copy explains consequences such as future-only edits and iCloud state.

### Empty and error states

- Empty states name one useful action: Log first food, Start Upper A, or Add measurement.
- Use one restrained SF Symbol, not an illustration.
- Errors preserve entered data and provide Retry where meaningful.
- Technical CloudKit/SwiftData language is prohibited in user-facing copy.

### Motion and haptics

- Use standard push and sheet transitions.
- Local state transitions complete in roughly 150–220 ms with ease-out behavior.
- Check completion may combine a subtle scale/opacity change with success haptic.
- Finish Workout uses a firm confirmation haptic after persistence succeeds.
- Milestones animate once when first acknowledged; no confetti.
- Under Reduce Motion, use an instant state change or crossfade.

### App icon

- Near-black neutral field with one Momentum Pulse continuous-loop mark suggesting a four-step cycle without literal dumbbells, faces, flames, or letters.
- Use a simple filled silhouette that survives small notification and Settings sizes.
- No gradients, text, numbers, gloss highlights, or photographic detail.

## Do's and Don'ts

### Do:

- **Do** make the next useful action the strongest element on Today.
- **Do** use native iOS navigation, controls, sheets, lists, and SF Symbols.
- **Do** test every primary flow in bright light and dark appearance on the physical iPhone 16 Pro Max.
- **Do** keep content opaque and reserve Liquid Glass for navigation and interactive action surfaces.
- **Do** use Momentum Pulse only for action, selection, or earned emphasis.
- **Do** preserve at least 44-by-44-point targets and Dynamic Type through accessibility sizes.
- **Do** pair color with symbols, labels, patterns, or numeric values.
- **Do** write direct, nonjudgmental copy that names the current state and next action.
- **Do** keep ordinary surface corners between 10 and 16 points.

### Don't:

- **Don't** build a gym-bro interface from black, neon green, flames, aggressive slogans, or pseudo-military language.
- **Don't** use childish gamification with coins, cartoon mascots, confetti, streak freezes, or manipulative loss warnings.
- **Don't** imitate sterile medical dashboards or make self-care feel diagnostic.
- **Don't** transplant a web-dashboard card grid onto iPhone; nested cards, tiny labels, and custom global navigation are forbidden.
- **Don't** use decorative glassmorphism, gradients, or motion that competes with logging.
- **Don't** apply glass to every panel or create multiple ungrouped `GlassEffectContainer` instances.
- **Don't** pair a one-point border with a wide soft shadow, use side-stripe accents, gradient text, or card radii above 16 points.
- **Don't** use tiny uppercase tracked eyebrows, numbered decorative section markers, or hard-coded font sizes.
- **Don't** use color alone for missed, skipped, due, recovery, complete, or target states.
- **Don't** show a timer, estimated one-repetition maximum, diagnostic skincare claim, or automatic treatment progression.
