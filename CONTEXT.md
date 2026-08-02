# Personal Routine Tracker

A personal system for planning and recording one person's fitness, nutrition, skincare, and hair-care routines.

## Language

**Routine Owner**:
The sole person whose highly customized routines, reminders, and daily records are managed by the app.
_Avoid_: User, account, member

## Fitness

**Workout Cycle**:
The repeating ordered sequence Upper A → Lower A → Upper B → Lower B. It continues across calendar-week boundaries and advances only when a workout is finished.
_Avoid_: Weekly schedule, workout week

**Workout Session**:
An actual attempt at the next workout in the Workout Cycle. Tapping Finish Workout completes the session regardless of individually skipped sets or exercises.
_Avoid_: Workout day

**Recovery Day**:
An intentionally workout-free day required between particular Workout Sessions. It is neutral in adherence calculations and never breaks a streak.
_Avoid_: Missed day, break day

**Due Workout**:
The next workout in the Workout Cycle once its required Recovery Days have elapsed. It remains due until finished and never creates catch-up workouts.
_Avoid_: Scheduled workout

**Skipped Workout**:
A workout opportunity the Routine Owner deliberately declines. It does not advance the Workout Cycle.

**Missed Workout**:
A due workout whose opportunity passes without action. It does not advance the Workout Cycle.

**Working Set**:
A load-bearing exercise set recorded in kilograms, distinct from an untracked warm-up set.
_Avoid_: Set

## Nutrition

**Food Entry**:
A named food or meal with manually entered calories and protein.
_Avoid_: Macro entry

**Nutrition Target**:
An editable daily calorie goal and protein goal used to evaluate nutrition adherence.
_Avoid_: Diet plan

**Nutrition Target Range**:
The acceptable calorie interval and minimum protein amount used to judge a day's target adherence.
_Avoid_: Exact calorie target

**Body Recomposition**:
The Routine Owner's goal of reducing overall body fat while gaining or preserving muscle.
_Avoid_: Belly-fat reduction, weight loss

**Weight Trend**:
The seven-day average of recorded body weights, used instead of a single measurement to assess progress.
_Avoid_: Current weight

**Body Measurement**:
An optional gym-recorded body weight or weekly waist measurement used to assess Body Recomposition.
_Avoid_: Check-in

## Personal Care

**Care Task**:
A scheduled skincare or hair-care action that can be completed independently.
_Avoid_: Step, reminder

**Care Routine**:
A due group of related Care Tasks, such as morning skincare, night skincare, or hair care.
_Avoid_: Care reminder

**Care Schedule**:
The Routine Owner's editable assignment of Care Routines and Care Products to times or recurrence patterns. It changes only through an explicit edit.
_Avoid_: Treatment progression

**Care Product**:
A skincare or hair-care item identified by its purpose or active ingredient rather than its brand.
_Avoid_: Brand, product name

## Adherence

**Adherence Day**:
A calendar day's completion percentage across activities due that day. Recovery Days add no workout obligation.
_Avoid_: Active day

**Category Streak**:
Consecutive eligible days on which the due activities in one category—workout, nutrition logging, or personal care—were completed.
_Avoid_: Global streak
