# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

Ruby gem (`rrule`) for expanding iCalendar recurrence rules. Takes an RRULE string like `FREQ=DAILY;COUNT=3` and generates occurrence dates/times. Runtime dependency on ActiveSupport (>= 2.3), requires Ruby >= 2.6.

The grammar is [RFC 5545 §3.3.10](https://datatracker.ietf.org/doc/html/rfc5545#section-3.3.10); the gem and its README still cite the obsoleted [RFC 2445](https://datatracker.ietf.org/doc/html/rfc2445) (see [issue #46](https://github.com/square/ruby-rrule/issues/46)).

## Commands

```bash
bundle install                          # Install dependencies
bundle exec rake                        # Run tests + RuboCop (default task)
bundle exec rspec                       # Tests only
bundle exec rspec spec/rule_spec.rb:42  # Single test by line number
bundle exec rubocop                     # Lint
bundle exec rubocop -A                  # Lint with autofix
appraisal install                       # Install appraisal gemfiles
appraisal rake                          # Run tests against all ActiveSupport versions (7.0, 7.1, 7.2, 8.0)
```

## Architecture

**See [ARCHITECTURE.md](ARCHITECTURE.md) for the full design** — the day-of-year index system, Context's cache lifecycle, timeset expansion, and timezone handling. The summary below is the orientation layer.

The iteration pipeline in `Rule#each` works as: **Frequency** produces candidate days → **Filters** reject non-matching days → **Generator** combines days with timesets → results are yielded.

### Key components

- **`RRule::Rule`** (`lib/rrule/rule.rb`): Public API entry point. Includes `Enumerable`. Parses RRULE strings in `parse_options` and drives the iteration loop in `#each`. Also accessible via `RRule.parse(rrule, **options)`.

- **`RRule::Context`** (`lib/rrule/context.rb`): Maintains year/month state and caches computed day-of-year masks, weekday arrays, and positional weekday data. `#rebuild(year, month)` is the only public mutator — called from `Frequency#advance` on month changes — and it clears the memoized arrays on a year change. Note the cached arrays run 7 days past year-end, so they are 372 entries long, not 365.

- **Frequencies** (`lib/rrule/frequencies/`): Base class `Frequency` with subclasses for each FREQ type (Secondly, Minutely, Hourly, Daily, Weekly, SimpleWeekly, Monthly, Yearly). Each defines `possible_days` and a private `advance_by`. Factory method `Frequency.for_options` selects the class and raises `InvalidRRule` on a bad FREQ. `SimpleWeekly` is a fast path used only when a WEEKLY rule specifies **none** of BYDAY/BYWEEKNO/BYYEARDAY and has no BYMONTH — `FREQ=WEEKLY;BYDAY=MO` uses the full `Weekly` pipeline, not `SimpleWeekly`.

- **Filters** (`lib/rrule/filters/`): Each implements `reject?(day_index)`. Applied as a chain — any filter rejecting a day excludes it. Filters: ByMonth, ByMonthDay, ByWeekDay, ByWeekNumber, ByYearDay.

- **Generators** (`lib/rrule/generators/`): `AllOccurrences` (default) and `BySetPosition` (when BYSETPOS is present). Core method `combine_dates_and_times` merges day indices with timesets to produce DateTime objects.

- **`RRule::Humanizer`** (`lib/rrule/humanizer.rb`): Converts rules to human-readable strings. Covers all seven frequencies; `UNTIL` is unimplemented and raises.

- **`RRule::Weekday`** (`lib/rrule/weekday.rb`): Represents a weekday with optional ordinal (e.g., "2MO" = second Monday).

## Testing

- RSpec with `Time.zone` set to `America/Los_Angeles` in spec_helper
- Uses Appraisal to test against multiple ActiveSupport versions
- CI runs on Ruby 3.2, 3.3, 3.4 via GitHub Actions
- CI also verifies appraisal gemfiles are up to date
