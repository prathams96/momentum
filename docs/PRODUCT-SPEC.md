# Momentum Product Specification

## 1. Product summary

Momentum is a native, personal-only iPhone app for executing four connected routines:

- a continuous four-workout Upper/Lower cycle with recovery-driven scheduling;
- manual calorie and protein tracking by named food entry;
- calendar-based skincare routines using generic roles and active ingredients;
- interval-based hair care.

The primary screen is Today. It answers three questions immediately: **What is due? What can I log now? How consistent have I been?**

### Initial release target

- Device: iPhone 16 Pro Max
- OS: iOS 26.0.1; deployment target iOS 26.0
- App name: Momentum
- Bundle identifier: `com.pratham.momentum`
- Audience: one Routine Owner
- Distribution: signed with the Routine Owner's paid Apple Developer account

## 2. Goals and non-goals

### Goals

1. Make today's obligations legible within two seconds of launch.
2. Preserve the correct workout sequence despite missed, skipped, or early sessions.
3. Make repeated food, set, and care logging fast enough for daily use.
4. Show honest consistency without penalizing recovery or using manipulative gamification.
5. Keep data private, available offline, synchronized through the Routine Owner's private iCloud database, and exportable.

### Non-goals for v1

- Multiple users, login, social sharing, coaching, or leaderboards
- Apple Health or Amazfit integration
- Rest, set, or workout timers
- Food search, barcode scanning, automatic nutrition lookup, or meal planning
- AI recommendations or automatic health-plan progression
- Progress photos
- Face ID lock
- Server backend or analytics SDK

## 3. Canonical rules

The domain glossary in [`CONTEXT.md`](../CONTEXT.md) and ADRs in [`docs/adr`](./adr/) are normative. If this specification conflicts with them, resolve the contradiction before implementation.

### Domain day

- A Domain Day runs from 03:00 local time through 02:59:59 the next calendar day.
- The cutoff is editable; 03:00 is the seed value.
- Workouts, food, care, measurements, streaks, and the heatmap use the same Domain Day calculation.
- Time-zone changes preserve absolute timestamps but recompute displayed Domain Days using the current local time zone. The app must show a confirmation before a time-zone change alters recent day attribution.

### Historical truth

- Routine and target edits affect future activities only.
- A Workout Session snapshots the workout name, exercises, prescriptions, chosen alternatives, and relevant targets.
- Food Entries snapshot their name, calories, and protein.
- Care completions snapshot their routine and tasks.
- Editing or deleting history recalculates totals, streaks, and—when completed workouts change—the current Workout Cycle.

## 4. Information architecture

Momentum uses four top-level tabs, each with an independent navigation history:

1. **Today** — due activities, recovery state, nutrition progress, quick actions, and recent consistency
2. **History** — calendar/heatmap exploration and day details
3. **Plans** — workout, recovery, nutrition-target, care, and notification editing
4. **Progress** — body measurements, nutrition trends, exercise performance, and adherence

Settings is accessed from the Today navigation toolbar. Logging and editing tasks appear in native sheets; an active Workout Session uses an immersive full-screen flow.

## 5. Onboarding

On first launch:

1. Explain that Momentum is private, local-first, and built for one person.
2. Preview the seeded Workout Cycle and care routines.
3. Ask which workout is next; preselect **Upper A**.
4. Ask whether the next workout is due today; default to yes.
5. Show editable seed targets: 2,400 kcal, green range 2,300–2,500 kcal, and 150 g protein.
6. Show editable notification times.
7. Explain notification value, then request permission in context.
8. Show iCloud sync state and allow the app to continue locally if iCloud is unavailable.

There is no signup, profile creation, tutorial carousel, or demand for measurement data.

## 6. Today

### Required content order

1. Large navigation title and date
2. Due Workout or Recovery Day state
3. Nutrition status with **Log Food** quick action
4. Due Care Routines ordered by time
5. Compact consistency heatmap and current category streaks

### Workout state

- **Due:** name, focus, due/overdue label, exercise count, and Start Workout action
- **Recovery:** explicit Recovery Day label, next workout, next eligible Domain Day, and Start Early action
- **Overdue:** retain the same next workout; never create catch-up sessions
- **Started:** resume the active session

### Nutrition state

- Show consumed calories against the 2,300–2,500 green range.
- Show consumed protein against the 150 g minimum.
- Show whether the day is open or finalized.
- Offer Log Food and Finish Logging Today.
- Exact targets and range are editable.

### Care state

- Each Care Routine is one activity with expandable tasks.
- A routine is complete when all required tasks are complete or a valid conditional alternative is selected.
- Waiting periods are written guidance only; they never start timers.
- Conditional tasks do not reduce adherence when they do not apply.

## 7. Workout Cycle and scheduling

### Seed cycle

The ordered cycle is:

1. Upper A
2. Lower A
3. Upper B
4. Lower B

The initial next workout is Upper A.

### Recovery transitions

| Completed workout | Intervening Recovery Days | Next workout |
|---|---:|---|
| Upper A | 0 | Lower A |
| Lower A | 1 | Upper B |
| Upper B | 0 | Lower B |
| Lower B | 2 | Upper A |

The next due Domain Day is `completion day + recovery days + 1`. This yields workout, workout, recovery, workout, workout, recovery, recovery when followed exactly, but it is never anchored to weekdays.

### Missed and skipped behavior

- If a Due Workout is not finished by Domain Day cutoff, record that day as Missed.
- A missed workout remains the Due Workout on the next Domain Day.
- Skip Today records an intentional skip and keeps the same workout due the next day.
- From the workout notification, support Start, Remind in 30 Minutes, and Skip Today.
- Never queue more than one Due Workout and never suggest doubling up.

### Start Early

- Recovery screens offer Start Early.
- Explain the remaining recovery before confirmation; never block the action.
- Finishing early anchors all subsequent recovery dates to the actual completion Domain Day.

### Session completion

- A Workout Session begins when Start Workout is confirmed.
- Tapping Finish Workout always records a completed session and advances the cycle.
- There is no partial-workout status.
- Sets and exercises may be individually skipped.
- If unfinished sets remain, confirmation copy is factual: “Some sets are unfinished. Finish this workout anyway?”

### Session logging

For each working set, support:

- weight in kilograms;
- repetitions;
- reps in reserve;
- completed or skipped;
- optional note.

Warm-up sets are not tracked. Previous-session values are visible and can be copied. An exercise can be swapped to a configured alternative without modifying past sessions.

### Progression suggestion

When every prescribed working set reaches the top of its rep range, suggest a small weight increase for the next occurrence. The suggestion:

- is never applied automatically;
- can be accepted, edited, or dismissed;
- must respect the load increment entered for that exercise.

### Seed workout content

Use [`UL_4_Day_Workout_Plan.md`](../UL_4_Day_Workout_Plan.md) as the source for exercise order, set counts, rep ranges, notes, substitutions, and progression guidance. Ignore its weekday schedule; ADR 0001 supersedes that portion. For every `2–3` or `1–2` set range, seed the higher count while keeping it editable.

## 8. Nutrition

### Seed targets

- Display target: 2,400 kcal
- Green range: 2,300–2,500 kcal
- Protein minimum: 150 g

These are editable and should be presented as starting values, not medical prescriptions.

### Food Entry

A Food Entry contains:

- name, required;
- calories, required, nonnegative integer;
- protein grams, required, nonnegative decimal;
- serving multiplier, default 1.0;
- Domain Day and timestamp.

The entered calories and protein represent one base serving; totals equal base values multiplied by the serving multiplier.

### Reuse

- Recent foods sort by last use.
- Favorites are explicitly pinned.
- Selecting either prepopulates values for editing before saving.
- Duplicate and swipe-to-delete are supported.

### Finalizing a day

- Finish Logging Today records explicit logging completion and earns the nutrition logging streak.
- Entries remain editable afterward and totals/adherence recompute.
- If unfinished at 22:00, issue a reminder with Open Log and Remind in 30 Minutes.
- If a night-care notification is also due at 22:00, coalesce them into one Evening Check-in notification that opens Today.

## 9. Body measurements

- Weight is recorded at the gym, manually or from the Finish Workout flow.
- Do not schedule a weight notification.
- Waist circumference is optional and may be entered manually; show it as due after seven days without sending a notification.
- Use kilograms and centimeters.
- Present a seven-day weight average when enough data exists; show raw observations alongside it.
- Never label a short-term increase or decrease as success or failure.

## 10. Personal care

Product brands are forbidden in seeded data and UI. Identify Care Products only by purpose or active ingredient.

### Morning care — daily at 09:00

1. Choose one valid cleanse path:
   - Oily: salicylic-acid cleanser
   - Normal/dry: water rinse
2. Moisturizer
3. Wait 30–60 seconds, displayed as instruction only
4. SPF 50 sunscreen

### Night care — daily at 22:00

| Day | Routine |
|---|---|
| Monday, Thursday | Salicylic-acid cleanser; pat dry; wait 10–20 minutes; adapalene 0.1%, pea-sized over face; wait 2–5 minutes; moisturizer |
| Wednesday, Saturday | Salicylic-acid cleanser; azelaic acid, pea-sized; wait 1–2 minutes; moisturizer |
| Tuesday, Friday, Sunday | Salicylic-acid cleanser; moisturizer |

- Do not automatically increase adapalene frequency.
- The Routine Owner started adapalene recently, has used it twice, and reports good tolerance.
- All care schedules remain manually editable.
- Glycolic acid and other paused items are not seeded as active tasks.

### Hair care — 08:00 on an alternating 3/4-day cadence

1. Salicylic-acid shampoo
2. Massage scalp gently for 1–2 minutes
3. Rinse thoroughly
4. Conditioner on hair lengths only, avoiding scalp
5. Rinse after 2–3 minutes

Seed the cadence from Wednesday/Saturday. If hair care is missed, roll it to the next Domain Day; after completion, continue the alternating interval from the actual completion day.

### Post-workout care

After Finish Workout, ask “Heavy sweating?” If yes:

1. add Wash Face to Today;
2. ask “Going outdoors again?”;
3. if yes, add Reapply Sunscreen.

## 11. Notifications

All times are editable. Seed times:

| Purpose | Time |
|---|---:|
| Hair care | 08:00 |
| Morning care | 09:00 |
| Workout on a due day | 18:30 |
| Night care | 22:00 |
| Unfinished nutrition logging | 22:00 |

Rules:

- Use local notifications only.
- Reschedule notifications after plan edits, completion, skip, time-zone change, or app foregrounding.
- Cancel obsolete pending requests immediately.
- Care notifications support Done, Remind in 30 Minutes, and Skip Today.
- Done marks the whole Care Routine complete and must be undoable from Today/History.
- Notification denial never blocks the app; Settings explains how to enable notifications.

## 12. Adherence and gamification

### Heatmap

- Display 16 weeks initially and allow horizontal access to older history.
- Rows are weekdays and columns are weeks, matching the GitHub mental model.
- Each Domain Day receives a 0–100 completion score from due activities: Due Workout, nutrition finalization, morning care, night care, hair care when due, and generated post-workout care.
- Each due activity has equal weight. Recovery contributes no due activity.
- Use five visual intensity levels: no obligation/no data, 1–25, 26–50, 51–75, and 76–100.
- Use shape, VoiceOver labels, and numeric detail so color is never the only signal.

### Category streaks

- **Workout:** consecutive Due Workout opportunities finished without a Missed or Skipped Workout; Recovery Days are neutral.
- **Nutrition logging:** consecutive Domain Days explicitly finalized.
- **Personal care:** consecutive Domain Days on which all due Care Routines were completed; a missed rolled hair routine breaks the original day’s streak.

### Milestones

Support restrained acknowledgements for:

- 10, 25, and 50 completed workouts;
- new category-streak records;
- exercise bests;
- consecutive days within Nutrition Target Range.

No coins, levels, streak freezes, confetti, or punitive messages.

## 13. History and correction

- History offers an all-category heatmap, category filter, calendar navigation, and chronological day detail.
- Entries can be backdated, edited, and deleted.
- Destructive deletion requires confirmation and explains downstream effects.
- Before deleting or changing a completed Workout Session, preview the resulting next workout and due date.
- Undo simple same-session changes where practical.

## 14. Progress

Required views:

- body weight observations and seven-day average;
- waist measurements;
- daily calories with target range;
- daily protein with minimum target;
- exercise total volume over time;
- highest completed weight and best repetitions at each weight;
- adherence and category streak history.

Do not compute estimated one-repetition maximums.

## 15. Plans and settings

### Plans

- Reorder Workout Cycle templates.
- Add, remove, reorder, and edit exercises and alternatives.
- Edit set count, rep range, notes, load increment, and recovery days after each workout.
- Edit nutrition targets and target range.
- Edit care recurrence, task order, generic product role/active, instructions, and notification time.
- Historical snapshots remain unchanged.

### Settings

- Notification permission/status and per-routine times
- Domain Day cutoff
- Units, seeded as kg and cm
- iCloud sync status
- CSV export
- About and data explanation
- Reset all data behind a typed/destructive confirmation

## 16. Export

Export UTF-8 CSV files through the native share sheet:

- `workouts.csv`
- `food.csv`
- `measurements.csv`
- `care.csv`
- `adherence.csv`

Use ISO 8601 timestamps plus a Domain Day column. Include stable record IDs and snapshot values so exports remain understandable without the app.

## 17. Empty, error, and offline states

- Empty states teach the next action: Log First Food, Start Upper A, or Add First Measurement.
- iCloud unavailable: continue locally and show status only in Settings unless action is required.
- Notification denied: show one contextual explanation, then defer to Settings.
- Save failure: retain the draft and offer Retry; never dismiss entered data.
- Corrupt or duplicate singleton settings: repair deterministically and record diagnostics without exposing technical language.

## 18. Acceptance criteria

The v1 product is ready when:

1. The continuous Workout Cycle passes all recovery, miss, skip, early-start, edit, deletion, cutoff, and time-zone scenarios.
2. Every seeded workout and generic care task matches the source plans and decisions above.
3. All primary logging flows work offline and survive app termination.
4. Private iCloud sync works between two test installations on the same Apple ID.
5. Pending notifications always reflect the current plans and Due Workout.
6. History edits correctly recalculate totals, streaks, and the next workout.
7. CSV exports open correctly in Numbers and retain Unicode names.
8. Today, Workout Session, Food Entry, Care Routine, History, and Progress pass VoiceOver, Dynamic Type, light/dark, Reduce Motion, Reduce Transparency, and Increased Contrast checks.
9. No v1 non-goal or product brand appears in the build.
