# Architecture

This document explains how the `rrule` gem works internally — how an RRULE string becomes a sequence of dates. For usage, see the [README](README.md). For the recurrence grammar itself, see [RFC 5545 §3.3.10 (Recurrence Rule)](https://datatracker.ietf.org/doc/html/rfc5545#section-3.3.10), which obsoletes the [RFC 2445](https://datatracker.ietf.org/doc/html/rfc2445) text this gem was originally written against.

File paths below link to the source they describe.

## The Big Picture

When you write:

```ruby
rule = RRule::Rule.new('FREQ=WEEKLY;BYDAY=MO,WE,FR;COUNT=10', dtstart: Time.zone.parse('2024-01-01'))
rule.all
```

The library:

1. **Parses** the RRULE string into an options hash
2. **Selects** a Frequency strategy based on `FREQ=`
3. **Builds** a chain of Filters from the `BY*=` parameters
4. **Iterates** through time intervals, using the Frequency to propose candidate days, the Filters to narrow them down, and a Generator to combine surviving days with times

Here's the data flow for each iteration step:

```
                    ┌────────────┐
                    │  Frequency │
                    │            │
                    │ "What days │
                    │  are in    │
                    │  this      │
                    │  interval?"│
                    └─────┬──────┘
                          │
                   array of day-of-year
                   indices (0-indexed)
                          │
                          ▼
                  ┌───────────────┐
                  │   Filters[]   │
                  │               │
                  │ "Should this  │
                  │  day be       │
                  │  rejected?"   │
                  └───────┬───────┘
                          │
                   surviving day indices
                   (nils where rejected)
                          │
                          ▼
                  ┌───────────────┐
                  │   Generator   │
                  │               │
                  │ "Combine days │
                  │  with times"  │
                  └───────┬───────┘
                          │
                    DateTime objects
                          │
                          ▼
                  ┌───────────────┐
                  │   Rule#each   │
                  │               │
                  │  Applies      │
                  │  COUNT, UNTIL,│
                  │  EXDATE, and  │
                  │  dtstart      │
                  │  boundary     │
                  │  checks       │
                  └───────────────┘
```

After yielding results, the Frequency advances `current_date` to the next interval and the loop repeats.

## Classes in Detail

### [`RRule::Rule`](lib/rrule/rule.rb) — the public API

The entry point. Includes `Enumerable`.

**Construction:** Parses an RRULE string into an `options` hash via `parse_options`. This is where the RFC text parameters (`FREQ`, `BYDAY`, `BYMONTH`, etc.) become Ruby data structures.

Defaults are then applied based on frequency type, but **only for rules that specify none of `BYWEEKNO`, `BYYEARDAY`, or `BYDAY`**. That guard matters more than it looks — it is the single condition behind three otherwise-unrelated behaviors:

| Frequency | Default applied (when the guard holds) |
|---|---|
| `YEARLY` | `bymonth = [dtstart.month]` (unless `BYMONTHDAY` + `COUNT`), `bymonthday = [dtstart.day]` |
| `MONTHLY` | `bymonthday = [dtstart.day]` |
| `WEEKLY` | `byweekday = [Weekday.new(dtstart.wday)]` and the `simple_weekly` flag (see [SimpleWeekly](#frequencies--how-time-advances)) |

So `FREQ=MONTHLY` gets `bymonthday = [dtstart.day]`, but `FREQ=MONTHLY;BYDAY=2MO` gets no `bymonthday` at all.

One subtle detail: `BYDAY` values like `2MO` (second Monday) are split into two separate lists:
- `options[:byweekday]` — plain weekdays (no ordinal), used by Filters
- `options[:bynweekday]` — nth weekdays (with ordinal), used by Context's `day_of_year_mask`

**Public methods:**
- `all(limit:)` — all occurrences up to `max_year`
- `between(start_date, end_date, limit:)` — occurrences in a range
- `from(start_date, limit:)` — occurrences starting from a date (limit required)
- `each(floor_date:)` — the core iteration loop (yields DateTime/Date objects)
- `next` — lazy: returns the next occurrence from an internal enumerator
- `humanize` — English description of the rule
- `is_finite?` — true if COUNT or UNTIL is set
- `to_s` — the original RRULE string

Iteration is bounded by `max_year` (default `9999`), so an infinite rule still terminates.

**The iteration loop** (`each`) does:
1. Resolve `floor_date` — **if `COUNT` is set, or `INTERVAL > 1`, the floor is forced back to `dtstart`**, because both are defined relative to `dtstart` and can't be evaluated from an arbitrary midpoint. This is why `from`/`between` on a `COUNT` rule still walks the recurrence from the beginning.
2. Build a `Context` for the starting year/month
3. Instantiate Filters from the relevant `BY*` options
4. Pick a Generator (`BySetPosition` if BYSETPOS is set, otherwise `AllOccurrences`)
5. Create a Frequency instance and loop:
   - Call `frequency.next_occurrences` (which calls `possible_days` → filters → generator)
   - Skip results before `dtstart` or `floor_date`
   - Stop if `UNTIL` or `COUNT` is exceeded, or year exceeds `max_year`
   - Skip any date in the `exdate` list
   - Yield the result

### [`RRule::Context`](lib/rrule/context.rb) — shared year-level state

Context is the performance backbone. It precomputes and caches arrays that map day-of-year index (0-based) to various properties. Values below are for 2025 (a non-leap year starting on a Wednesday):

| Method | Returns | Example |
|---|---|---|
| `month_by_day_of_year` | month number for each day | `[1, 1, ..., 2, 2, ..., 12]` |
| `month_day_by_day_of_year` | day-of-month for each day | `[1, 2, ..., 31, 1, 2, ...]` |
| `negative_month_day_by_day_of_year` | day-of-month counted from the end (`-1` is the last day) | `[-31, -30, ..., -1, -28, ...]` |
| `weekday_by_day_of_year` | weekday index (0=Sun) | `[3, 4, 5, 6, ...]` |
| `week_number_by_day_of_year` | ISO week number | `[1, 1, ..., 52]` |
| `negative_week_number_by_day_of_year` | ISO week counted from the end | `[-52, -52, ...]` |
| `elapsed_days_in_year_by_month` | cumulative days by month, 1-indexed with a leading `0` | `[0, 31, 59, 90, ...]` |
| `year_length_in_days` | 365 or 366 | `365` |
| `next_year_length_in_days` | same, for `year + 1` | `365` |
| `first_day_of_year` | `Date` for Jan 1 | `2025-01-01` |
| `first_weekday_of_year` | `wday` of Jan 1 | `3` |

**These arrays run seven days past the end of the year.** `days_in_year` is built as `first_day_of_year..end_of_year + 7.days`, so for 2025 each array holds 372 entries, not 365. The overhang is what lets a week straddling New Year's — and `ByYearDay`'s cross-year checks — index past December 31 without a bounds error.

**Cache lifecycle:** `rebuild(year, month)` is the only public mutator. `Rule#each` calls it once to prime the Context, and thereafter [`Frequency#advance`](#frequencies--how-time-advances) calls it whenever iteration crosses a month boundary. On a *year* change it calls the private `reset_year`, which nils out every memoized array above so the next access recomputes for the new year. On a *month* change within the same year the cached arrays survive, and only the mask below is rebuilt.

`SimpleWeekly` is the exception: it overrides `next_occurrences` without calling `advance`, so it never triggers a rebuild. That's safe precisely because it reads none of the cached arrays — only `options`, `dtstart`, and `tz`.

Context also handles **nth weekday matching** (e.g., "2nd Monday of the month") via `day_of_year_mask` — a boolean array where `true` marks days that match an nth weekday rule. It is populated only when `bynweekday` is present: per-month for MONTHLY rules, and for YEARLY rules across either the BYMONTH months or the whole year.

### [Frequencies](lib/rrule/frequencies) — how time advances

All frequency classes inherit from [`Frequency`](lib/rrule/frequencies/frequency.rb) and implement two methods — a public `possible_days` and a private `advance_by`:

| Class | `possible_days` returns | `advance_by` |
|---|---|---|
| `Yearly` | All days in the year (0..364/365) | `{ years: interval }` |
| `Monthly` | All days in the current month | `{ months: interval }` |
| `Weekly` | Up to 7 days from current date to end of week (respects WKST) | `{ days: N }` where N accounts for interval and WKST |
| `Daily` | Just today's day-of-year | `{ days: interval }` |
| `Hourly` | Just today's day-of-year, overrides `timeset` with current hour | `{ hours: interval }` |
| `Minutely` | Just today's day-of-year, overrides `timeset` with current hour+minute | `{ minutes: interval }` |
| `Secondly` | Just today's day-of-year, overrides `timeset` with current h+m+s | `{ seconds: interval }` |

The base `Frequency#next_occurrences` method orchestrates the pipeline: get `possible_days`, apply filters (setting rejected entries to `nil`), pass to generator, then `advance`. `advance` is also the hook that keeps Context in sync — it calls `context.rebuild(year, month)` whenever the new date lands in a different month.

`Frequency.for_options` is the factory that maps `FREQ=` to a class, and raises `RRule::InvalidRRule` for a missing or unrecognized value.

**[`SimpleWeekly`](lib/rrule/frequencies/simple_weekly.rb)** is a special case — it bypasses the standard pipeline entirely, overriding `next_occurrences` to jump straight to the target weekday and advance by `interval.weeks`, with no day array and no filtering. It's a significant optimization for the most common weekly pattern.

It is selected only when **both** hold:

- `parse_options` set the internal `simple_weekly` flag — which happens for a `WEEKLY` rule specifying **none** of `BYDAY`, `BYWEEKNO`, or `BYYEARDAY` (the recurring weekday is inferred from `dtstart`), and
- the rule has no `BYMONTH`.

Note the first condition is about `BYDAY` being *absent*, not about it being simple: `FREQ=WEEKLY` uses `SimpleWeekly`, but `FREQ=WEEKLY;BYDAY=MO` falls through to the full `Weekly` pipeline even though it names a single weekday.

### [Filters](lib/rrule/filters) — narrowing candidates

Each filter answers one question: "should day index `i` be rejected?" Filters are stacked — if **any** filter rejects a day, it's excluded — so their order is irrelevant to the result.

| Filter | Rejects days where... | Reads from Context |
|---|---|---|
| [`ByMonth`](lib/rrule/filters/by_month.rb) | month doesn't match BYMONTH list | `month_by_day_of_year` |
| [`ByMonthDay`](lib/rrule/filters/by_month_day.rb) | day-of-month doesn't match (supports negative values like -1 for last day) | `month_day_by_day_of_year`, `negative_month_day_by_day_of_year` |
| [`ByWeekDay`](lib/rrule/filters/by_week_day.rb) | weekday doesn't match AND day isn't set in `day_of_year_mask` | `weekday_by_day_of_year`, `day_of_year_mask` |
| [`ByWeekNumber`](lib/rrule/filters/by_week_number.rb) | ISO week number doesn't match (supports negative) | `week_number_by_day_of_year`, `negative_week_number_by_day_of_year` |
| [`ByYearDay`](lib/rrule/filters/by_year_day.rb) | day-of-year doesn't match (supports negative and cross-year) | `year_length_in_days`, `next_year_length_in_days` |

Filters only exist when the corresponding `BY*` parameter was in the RRULE string (or implied by defaults in `parse_options`).

### [Generators](lib/rrule/generators) — making DateTimes

Generators take the filtered day indices and a timeset and produce actual DateTime objects. Both implement `combine_dates_and_times(dayset, timeset)`, the method the frequency calls:

- **[`AllOccurrences`](lib/rrule/generators/all_occurrences.rb)**: Converts each surviving day index to a date (`first_day_of_year + index`), then applies `process_timeset` to combine with hour/minute/second values. This is the default.

- **[`BySetPosition`](lib/rrule/generators/by_set_position.rb)**: Used when `BYSETPOS` is in the rule. First compacts the day array, then picks only the days at the specified positions (1-indexed, supports negative for "from end"), then applies `process_timeset`.

The base [`Generator#process_timeset`](lib/rrule/generators/generator.rb) handles `BYHOUR`, `BYMINUTE`, `BYSECOND` — it produces the cartesian product of all specified hours/minutes/seconds for each date, creating multiple occurrences per day when needed. When the timeset is blank (a Date-only rule) it returns the bare date untouched.

### [`RRule::Weekday`](lib/rrule/weekday.rb) — weekday with optional ordinal

A small value object. `Weekday.parse("2MO")` produces `Weekday.new(1, 2)` — index 1 (Monday, 0=Sunday) with ordinal 2 (second occurrence). Plain weekdays like `"MO"` have `ordinal = nil`.

### [`RRule::Humanizer`](lib/rrule/humanizer.rb) — English descriptions

Converts a rule to text like "every 2 weeks on Monday, Wednesday". `to_s` seeds a buffer with `"every"`, dispatches to a private method named after the frequency, and each of those appends to the buffer. All seven frequencies are covered: `secondly`, `minutely`, `hourly`, `daily`, `weekly`, `monthly`, `yearly`.

Option access uses two cooperating mechanisms:

- `initialize` calls `define_singleton_method` to expose every present option as a reader (`interval` becomes `interval_option`).
- `method_missing` catches anything else ending in `_option` and returns `nil` rather than raising, so the frequency methods can test `if bymonthday_option` without first checking whether the key exists.

**Known limitation:** `UNTIL` is not implemented — `humanize` raises `RuntimeError: Implement Until` for any rule with an `UNTIL` clause. `COUNT` is handled.

## The Day-of-Year Index System

The central design choice is that **days are represented as 0-based day-of-year indices** throughout the pipeline. This is why Context maintains all its lookup arrays indexed by day-of-year.

For example, January 1 is index 0, February 1 is index 31, etc. The Frequency produces these indices, Filters check them against Context's lookup arrays, and Generators convert them back to real dates by adding the index to `first_day_of_year`.

This means all Filters share a uniform interface (`reject?(i)` where `i` is a day-of-year index), and the Context's cached arrays make lookups O(1).

## Timeset Handling

The `timeset` option deserves special mention. For DateTime-based rules (not Date-only), `parse_options` creates:

```ruby
options[:timeset] = [{
  hour: byhour || dtstart.hour,
  minute: byminute || dtstart.min,
  second: bysecond || dtstart.sec
}]
```

Each value can be a single integer or an array (when `BYHOUR`, `BYMINUTE`, or `BYSECOND` specifies multiple values). The Generator produces the cartesian product, so `BYHOUR=9,17;BYMINUTE=0,30` yields 4 occurrences per day.

For sub-daily frequencies (Hourly, Minutely, Secondly), the frequency subclass overrides `timeset` to inject the current time component, since each iteration step represents a different time within the day.

## Timezone Handling

All time arithmetic uses ActiveSupport's timezone support. The Generator creates times via `Time.zone.local(...)` within a `Time.use_zone(context.tz)` block, ensuring DST transitions are handled correctly.

`Rule#floor_to_seconds_in_timezone` truncates sub-second precision to avoid floating-point comparison issues, and is applied at every boundary where a caller-supplied time enters the library: `dtstart` in the constructor (unless it's a plain `Date`), and the range arguments to `between` and `from`. Occurrences are compared with `<` / `>` against these floored values, so a `dtstart` carrying microseconds would otherwise silently exclude its own first occurrence.
