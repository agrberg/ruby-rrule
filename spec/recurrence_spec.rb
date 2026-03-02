# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RRule::Recurrence do
  describe '.new' do
    it 'raises ArgumentError for unknown attributes' do
      expect { described_class.new(frequency: 'DAILY', bogus: 1) }
        .to raise_error(ArgumentError, /Unknown attribute\(s\): bogus/)
    end

    it 'raises ArgumentError listing all unknown attributes' do
      expect { described_class.new(foo: 1, bar: 2) }
        .to raise_error(ArgumentError, /foo, bar/)
    end

    it 'accepts all valid attributes without error' do
      expect { described_class.new(frequency: 'DAILY', interval: 1, count: 5) }.not_to raise_error
    end
  end

  describe 'constants' do
    it 'exposes FREQUENCIES in order with named constants' do
      expect(described_class::FREQUENCIES.keys).to eq %w[YEARLY MONTHLY WEEKLY DAILY HOURLY MINUTELY]
      expect(described_class::DAILY).to eq 'DAILY'
    end

    it 'derives DAYS_OF_WEEK from Date::DAYNAMES with named constants' do
      expect(described_class::DAYS_OF_WEEK).to eq %w[SU MO TU WE TH FR SA]
      expect(described_class::SUNDAY).to eq 'SU'
      expect(described_class::MONDAY).to eq 'MO'
    end

    it 'exposes MONTHLY_OPTIONS with prefixed named constants' do
      expect(described_class::MONTHLY_OPTIONS).to eq %w[DATE NTH_DAY]
      expect(described_class::MONTHLY_DATE).to eq 'DATE'
      expect(described_class::MONTHLY_NTH_DAY).to eq 'NTH_DAY'
    end

    it 'exposes range constants' do
      expect(described_class::HOUR_OF_DAY_RANGE).to eq(0..23)
      expect(described_class::SECOND_OF_MINUTE_RANGE).to eq(0..59)
      expect(described_class::MONTH_OF_YEAR_RANGE).to eq(1..12)
      expect(described_class::DAY_OF_YEAR_RANGE).to include(1, 366, -1, -366)
      expect(described_class::WEEK_OF_YEAR_RANGE).to include(1, 53, -1, -53)
    end
  end

  describe 'frequency predicates' do
    it 'returns true for the matching frequency' do
      described_class::FREQUENCIES.each_key do |frequency|
        recurrence = described_class.new(frequency: frequency, interval: 1)
        expect(recurrence.public_send(:"#{frequency.downcase}?")).to be true
      end
    end

    it 'returns false for non-matching frequencies' do
      recurrence = described_class.new(frequency: 'DAILY', interval: 1)
      expect(recurrence).not_to be_yearly
      expect(recurrence).not_to be_monthly
      expect(recurrence).not_to be_weekly
      expect(recurrence).not_to be_hourly
      expect(recurrence).not_to be_minutely
    end
  end

  describe '#to_rrule' do
    subject do
      described_class.new(count: count, by_month_day: by_month_day, by_day: by_day, day_of_year: day_of_year,
                          frequency: frequency, hour_of_day: hour_of_day, interval: interval,
                          minute_of_hour: minute_of_hour, month_of_year: month_of_year,
                          by_set_pos: by_set_pos, repeat_until: repeat_until,
                          second_of_minute: second_of_minute,
                          week_of_year: week_of_year, week_start: week_start).to_rrule
    end

    let(:count) { nil }
    let(:by_month_day) { nil }
    let(:by_day) { nil }
    let(:day_of_year) { nil }
    let(:hour_of_day) { nil }
    let(:interval) { 10 }
    let(:minute_of_hour) { nil }
    let(:month_of_year) { nil }
    let(:by_set_pos) { nil }
    let(:repeat_until) { nil }
    let(:second_of_minute) { nil }
    let(:week_of_year) { nil }
    let(:week_start) { nil }

    context 'when frequency is yearly' do
      let(:frequency) { 'YEARLY' }

      it { is_expected.to eq 'FREQ=YEARLY;INTERVAL=10' }
    end

    context 'when frequency is monthly' do
      let(:frequency) { 'MONTHLY' }

      context 'when there is not specific day of month' do
        it { is_expected.to eq 'FREQ=MONTHLY;INTERVAL=10' }
      end

      context 'when there is a specific day of the month' do
        let(:by_month_day) { [20] }

        it { is_expected.to eq 'FREQ=MONTHLY;INTERVAL=10;BYMONTHDAY=20' }
      end

      context 'with multiple BYMONTHDAY values' do
        let(:by_month_day) { [1, 15] }

        it { is_expected.to eq 'FREQ=MONTHLY;INTERVAL=10;BYMONTHDAY=1,15' }
      end

      context 'when there is an nth day of the month' do
        let(:by_day) { ['MO'] }
        let(:by_set_pos) { [-1] }

        it { is_expected.to eq 'FREQ=MONTHLY;INTERVAL=10;BYDAY=MO;BYSETPOS=-1' }
      end
    end

    context 'when frequency is weekly' do
      let(:frequency) { 'WEEKLY' }

      context 'with set by_day' do
        let(:by_day) { ['MO'] }

        it { is_expected.to eq 'FREQ=WEEKLY;INTERVAL=10;BYDAY=MO' }
      end

      context 'with multiple by_day' do
        let(:by_day) { %w[MO WE FR] }

        it { is_expected.to eq 'FREQ=WEEKLY;INTERVAL=10;BYDAY=MO,WE,FR' }
      end

      context 'with a blank by_day' do
        let(:by_day) { ' ' }

        it { is_expected.to eq 'FREQ=WEEKLY;INTERVAL=10' }
      end
    end

    context 'when frequency is daily' do
      let(:frequency) { 'DAILY' }

      it { is_expected.to eq 'FREQ=DAILY;INTERVAL=10' }
    end

    context 'when frequency is hourly' do
      context 'with blank minute_of_hour' do
        let(:frequency) { 'HOURLY' }

        it { is_expected.to eq 'FREQ=HOURLY;INTERVAL=10' }
      end

      context 'with set minute_of_hour' do
        let(:frequency) { 'HOURLY' }
        let(:minute_of_hour) { [30] }

        it { is_expected.to eq 'FREQ=HOURLY;INTERVAL=10;BYMINUTE=30' }
      end

      context 'with multiple BYMINUTE values' do
        let(:frequency) { 'HOURLY' }
        let(:minute_of_hour) { [0, 30] }

        it { is_expected.to eq 'FREQ=HOURLY;INTERVAL=10;BYMINUTE=0,30' }
      end
    end

    context 'with COUNT' do
      let(:frequency) { 'DAILY' }
      let(:count) { 5 }

      it { is_expected.to eq 'FREQ=DAILY;INTERVAL=10;COUNT=5' }
    end

    context 'with UNTIL' do
      let(:frequency) { 'DAILY' }
      let(:repeat_until) { Time.utc(2026, 12, 31, 23, 59, 59) }

      it { is_expected.to eq 'FREQ=DAILY;INTERVAL=10;UNTIL=20261231T235959Z' }
    end

    context 'with WKST' do
      let(:frequency) { 'WEEKLY' }
      let(:week_start) { 'MO' }

      it { is_expected.to eq 'FREQ=WEEKLY;INTERVAL=10;WKST=MO' }
    end

    context 'with BYMONTH' do
      let(:frequency) { 'YEARLY' }
      let(:month_of_year) { [1, 6] }

      it { is_expected.to eq 'FREQ=YEARLY;INTERVAL=10;BYMONTH=1,6' }
    end

    context 'with BYHOUR' do
      let(:frequency) { 'DAILY' }
      let(:hour_of_day) { [9, 17] }

      it { is_expected.to eq 'FREQ=DAILY;INTERVAL=10;BYHOUR=9,17' }
    end

    context 'with BYSECOND' do
      let(:frequency) { 'MINUTELY' }
      let(:second_of_minute) { [0, 30] }

      it { is_expected.to eq 'FREQ=MINUTELY;INTERVAL=10;BYSECOND=0,30' }
    end

    context 'with BYYEARDAY' do
      let(:frequency) { 'YEARLY' }
      let(:day_of_year) { [1, -1] }

      it { is_expected.to eq 'FREQ=YEARLY;INTERVAL=10;BYYEARDAY=1,-1' }
    end

    context 'with BYWEEKNO' do
      let(:frequency) { 'YEARLY' }
      let(:week_of_year) { [1, 52] }

      it { is_expected.to eq 'FREQ=YEARLY;INTERVAL=10;BYWEEKNO=1,52' }
    end

    context 'with YEARLY+BYDAY (ordinal weekday)' do
      let(:frequency) { 'YEARLY' }
      let(:by_day) { ['+2TH'] }

      it { is_expected.to eq 'FREQ=YEARLY;INTERVAL=10;BYDAY=+2TH' }
    end

    context 'with multiple BYSETPOS values' do
      let(:frequency) { 'MONTHLY' }
      let(:by_set_pos) { [1, -1] }
      let(:by_day) { ['FR'] }

      it { is_expected.to eq 'FREQ=MONTHLY;INTERVAL=10;BYDAY=FR;BYSETPOS=1,-1' }
    end
  end

  describe '.from_rrule' do
    subject { described_class.from_rrule(rrule) }

    cases = [
      ['FREQ=MINUTELY;INTERVAL=10',
       { frequency: 'MINUTELY', interval: 10 }],
      ['FREQ=HOURLY;INTERVAL=10',
       { frequency: 'HOURLY', interval: 10 }],
      ['FREQ=HOURLY;INTERVAL=10;BYMINUTE=30',
       { frequency: 'HOURLY', interval: 10, minute_of_hour: [30] }],
      ['FREQ=DAILY;INTERVAL=10',
       { frequency: 'DAILY', interval: 10 }],
      ['FREQ=YEARLY;INTERVAL=10',
       { frequency: 'YEARLY', interval: 10 }],
      ['FREQ=MONTHLY;INTERVAL=10',
       { frequency: 'MONTHLY', interval: 10 }],
      ['FREQ=MONTHLY;INTERVAL=10;BYMONTHDAY=10',
       { frequency: 'MONTHLY', interval: 10, by_month_day: [10] }],
      ['FREQ=MONTHLY;INTERVAL=10;BYMONTHDAY=1,15',
       { frequency: 'MONTHLY', interval: 10, by_month_day: [1, 15] }],
      ['FREQ=MONTHLY;INTERVAL=10;BYDAY=WE;BYSETPOS=-1',
       { frequency: 'MONTHLY', interval: 10, by_set_pos: [-1], by_day: ['WE'] }],
      ['FREQ=WEEKLY;INTERVAL=10;',
       { frequency: 'WEEKLY', interval: 10 }],
      ['FREQ=WEEKLY;INTERVAL=10;BYDAY=WE',
       { frequency: 'WEEKLY', interval: 10, by_day: ['WE'] }],
      ['FREQ=WEEKLY;INTERVAL=2;BYDAY=MO,WE,FR',
       { frequency: 'WEEKLY', interval: 2, by_day: %w[MO WE FR] }],
      ['FREQ=DAILY;INTERVAL=1;COUNT=10',
       { frequency: 'DAILY', interval: 1, count: 10 }],
      ['FREQ=DAILY;INTERVAL=1;UNTIL=20261231T235959Z',
       { frequency: 'DAILY', interval: 1, repeat_until: Time.utc(2026, 12, 31, 23, 59, 59) }],
      ['FREQ=WEEKLY;INTERVAL=1;WKST=MO',
       { frequency: 'WEEKLY', interval: 1, week_start: 'MO' }],
      ['FREQ=YEARLY;INTERVAL=1;BYMONTH=1,6',
       { frequency: 'YEARLY', interval: 1, month_of_year: [1, 6] }],
      ['FREQ=YEARLY;INTERVAL=1;BYDAY=+2TH',
       { frequency: 'YEARLY', interval: 1, by_day: ['+2TH'] }],
      ['FREQ=DAILY;INTERVAL=1;BYHOUR=9,17',
       { frequency: 'DAILY', interval: 1, hour_of_day: [9, 17] }],
      ['FREQ=HOURLY;INTERVAL=1;BYMINUTE=0,30',
       { frequency: 'HOURLY', interval: 1, minute_of_hour: [0, 30] }],
      ['FREQ=MINUTELY;INTERVAL=1;BYSECOND=0,30',
       { frequency: 'MINUTELY', interval: 1, second_of_minute: [0, 30] }],
      ['FREQ=YEARLY;INTERVAL=1;BYYEARDAY=1,-1',
       { frequency: 'YEARLY', interval: 1, day_of_year: [1, -1] }],
      ['FREQ=YEARLY;INTERVAL=1;BYWEEKNO=1,52',
       { frequency: 'YEARLY', interval: 1, week_of_year: [1, 52] }],
    ].freeze

    recurrence_attrs = %i[
      by_day by_month_day by_set_pos count day_of_year frequency
      hour_of_day interval minute_of_hour month_of_year repeat_until
      second_of_minute week_of_year week_start
    ]

    cases.each do |(rrule, expected_values)|
      context "when given #{rrule}" do
        let(:rrule) { rrule }

        recurrence_attrs.each do |attr|
          it "initializes the #{attr} attr" do
            expect(subject.send(attr)).to eq expected_values[attr]
          end
        end
      end
    end
  end

  describe 'array attribute setters' do
    it 'coerces a scalar to a single-element array' do
      recurrence = described_class.new
      recurrence.by_day = 'MO'
      expect(recurrence.by_day).to eq ['MO']
    end

    it 'passes through an array unchanged' do
      recurrence = described_class.new
      recurrence.by_day = %w[MO WE FR]
      expect(recurrence.by_day).to eq %w[MO WE FR]
    end

    it 'sets nil for nil input' do
      recurrence = described_class.new
      recurrence.by_day = nil
      expect(recurrence.by_day).to be_nil
    end

    it 'normalizes empty array to nil' do
      recurrence = described_class.new
      recurrence.by_day = []
      expect(recurrence.by_day).to be_nil
    end

    it 'works for integer array attributes' do
      recurrence = described_class.new
      recurrence.hour_of_day = 9
      expect(recurrence.hour_of_day).to eq [9]
    end

    it 'works for by_set_pos' do
      recurrence = described_class.new
      recurrence.by_set_pos = -1
      expect(recurrence.by_set_pos).to eq [-1]
    end

    it 'works for by_month_day' do
      recurrence = described_class.new
      recurrence.by_month_day = 15
      expect(recurrence.by_month_day).to eq [15]
    end

    it 'works for minute_of_hour' do
      recurrence = described_class.new
      recurrence.minute_of_hour = 30
      expect(recurrence.minute_of_hour).to eq [30]
    end
  end

  describe '#repeat_until=' do
    it 'stores Time objects as UTC' do
      recurrence = described_class.new
      time = Time.new(2026, 6, 15, 12, 0, 0, '-05:00')
      recurrence.repeat_until = time
      expect(recurrence.repeat_until).to eq time.utc
      expect(recurrence.repeat_until.utc?).to be true
    end

    it 'parses RRULE date strings' do
      recurrence = described_class.new
      recurrence.repeat_until = '20261231T235959Z'
      expect(recurrence.repeat_until).to eq Time.utc(2026, 12, 31, 23, 59, 59)
    end

    it 'sets nil for nil input' do
      recurrence = described_class.new
      recurrence.repeat_until = nil
      expect(recurrence.repeat_until).to be_nil
    end

    it 'sets nil for empty string input' do
      recurrence = described_class.new
      recurrence.repeat_until = ''
      expect(recurrence.repeat_until).to be_nil
    end
  end

  describe '#monthly_option' do
    it 'returns DATE when by_month_day is set' do
      recurrence = described_class.new(frequency: 'MONTHLY', by_month_day: [15])
      expect(recurrence.monthly_option).to eq 'DATE'
      expect(recurrence).to be_by_month_day_option
      expect(recurrence).not_to be_by_set_pos_option
    end

    it 'returns NTH_DAY when by_set_pos and by_day are set' do
      recurrence = described_class.new(frequency: 'MONTHLY', by_day: ['FR'], by_set_pos: [-1])
      expect(recurrence.monthly_option).to eq 'NTH_DAY'
      expect(recurrence).to be_by_set_pos_option
      expect(recurrence).not_to be_by_month_day_option
    end

    it 'returns nil for non-monthly frequencies' do
      recurrence = described_class.new(frequency: 'DAILY', interval: 1)
      expect(recurrence.monthly_option).to be_nil
      expect(recurrence).not_to be_by_month_day_option
      expect(recurrence).not_to be_by_set_pos_option
    end

    it 'returns nil for monthly with no day specifier' do
      recurrence = described_class.new(frequency: 'MONTHLY', interval: 1)
      expect(recurrence.monthly_option).to be_nil
    end
  end

  describe 'BYDAY_PATTERN' do
    %w[MO TU WE TH FR SA SU +2TH -1FR 3WE].each do |valid|
      it "matches #{valid}" do
        expect(valid).to match(described_class::BYDAY_PATTERN)
      end
    end

    %w[XX 2 +MO2 MONDAY].each do |invalid|
      it "rejects #{invalid}" do
        expect(invalid).not_to match(described_class::BYDAY_PATTERN)
      end
    end
  end

  describe 'Comparable' do
    it 'compares frequencies by period' do
      smaller_frequency = described_class.new(frequency: 'YEARLY')
      larger_frequency = described_class.new(frequency: 'HOURLY')

      expect(smaller_frequency).to be < larger_frequency
      expect(larger_frequency).to be > smaller_frequency
      expect(larger_frequency.dup).to eq larger_frequency
    end

    it 'returns nil when compared to a non-Recurrence object' do
      recurrence = described_class.new(frequency: 'DAILY')
      expect(recurrence <=> 'not a recurrence').to be_nil
    end

    it 'returns 0 for equal frequencies' do
      a = described_class.new(frequency: 'WEEKLY', interval: 1)
      b = described_class.new(frequency: 'WEEKLY', interval: 5)
      expect(a <=> b).to eq 0
    end
  end
end
