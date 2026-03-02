# frozen_string_literal: true

require 'date'

module RRule
  # Pure Ruby data class representing an iCal RRULE recurrence pattern.
  # Handles RRULE string generation/parsing with named attributes and frequency comparison.
  #
  #   recurrence = RRule::Recurrence.new(frequency: 'DAILY', interval: 1)
  #   recurrence.to_rrule  # => "FREQ=DAILY;INTERVAL=1"
  #   recurrence.daily?    # => true
  #
  class Recurrence
    include Comparable

    def initialize(**attrs)
      unknown = attrs.keys - ATTRIBUTES
      raise ArgumentError, "Unknown attribute(s): #{unknown.join(', ')}" if unknown.any?

      attrs.each { |attr, value| public_send(:"#{attr}=", value) }
    end

    DAYS_OF_WEEK = Date::DAYNAMES.map { |name| const_set(name.upcase, name[0, 2].upcase) }.freeze

    FREQUENCIES = {
      'YEARLY' => 365,
      'MONTHLY' => 31,
      'WEEKLY' => 7,
      'DAILY' => 1,
      'HOURLY' => 1 / 24.0,
      'MINUTELY' => 1 / 24.0 / 60.0
    }.each_key do |freq|
      const_set(freq, freq)
      define_method(:"#{freq.downcase}?") { freq == frequency }
    end.freeze
    FREQ_ORDER = FREQUENCIES.keys.each_with_index.to_h.freeze

    MONTHLY_OPTIONS = %w[DATE NTH_DAY].each { |opt| const_set("MONTHLY_#{opt}", opt) }.freeze

    NTH_DAY_OF_MONTH = {
      first: 1,
      second: 2,
      third: 3,
      fourth: 4,
      last: -1,
      second_to_last: -2
    }.freeze

    DATE_OF_MONTH_RANGE = ((-28..-1).to_a + (1..28).to_a).freeze
    HOUR_OF_DAY_RANGE = (0..23).freeze
    MINUTE_OF_HOUR_RANGE = SECOND_OF_MINUTE_RANGE = (0..59).freeze
    MONTH_OF_YEAR_RANGE = (1..12).freeze
    DAY_OF_YEAR_RANGE = ((-366..-1).to_a + (1..366).to_a).freeze
    WEEK_OF_YEAR_RANGE = ((-53..-1).to_a + (1..53).to_a).freeze
    BYDAY_PATTERN = /\A[+-]?\d*(?:#{Regexp.union(DAYS_OF_WEEK).source})\z/.freeze
    UNTIL_PATTERN = /\A(?<Y>\d{4})(?<m>\d{2})(?<d>\d{2})T(?<H>\d{2})(?<M>\d{2})(?<S>\d{2})Z\z/.freeze

    ATTRIBUTES = %i[
      by_day by_month_day by_set_pos count day_of_year frequency hour_of_day interval
      minute_of_hour month_of_year repeat_until
      second_of_minute week_of_year week_start
    ].freeze

    ARRAY_ATTRIBUTES = %i[
      by_day by_month_day by_set_pos day_of_year hour_of_day minute_of_hour
      month_of_year second_of_minute week_of_year
    ].freeze

    attr_accessor(*(ATTRIBUTES - ARRAY_ATTRIBUTES - %i[repeat_until]))
    attr_reader :repeat_until, *ARRAY_ATTRIBUTES

    class << self
      def from_rrule(rrule)
        new(**attributes_from(parse_components(rrule)))
      end

      private

      def parse_components(rrule)
        rrule.split(';').each_with_object({}) do |pair, hash|
          next if pair.strip.empty?

          key, value = pair.split('=', 2)
          hash[key] = value
        end
      end

      def attributes_from(components)
        {
          by_day: split_list(components['BYDAY']),
          by_month_day: split_int_list(components['BYMONTHDAY']),
          by_set_pos: split_int_list(components['BYSETPOS']),
          count: components['COUNT']&.to_i,
          day_of_year: split_int_list(components['BYYEARDAY']),
          frequency: components['FREQ'],
          hour_of_day: split_int_list(components['BYHOUR']),
          interval: components['INTERVAL']&.to_i || 1,
          minute_of_hour: split_int_list(components['BYMINUTE']),
          month_of_year: split_int_list(components['BYMONTH']),
          repeat_until: components['UNTIL'],
          second_of_minute: split_int_list(components['BYSECOND']),
          week_of_year: split_int_list(components['BYWEEKNO']),
          week_start: components['WKST']
        }
      end

      def split_list(csv)
        return unless csv

        list = csv.split(',')
        list unless list.empty?
      end

      def split_int_list(csv)
        split_list(csv)&.map(&:to_i)
      end
    end

    ARRAY_ATTRIBUTES.each do |attr|
      define_method(:"#{attr}=") do |value|
        coerced = Array(value)
        instance_variable_set(:"@#{attr}", coerced.empty? ? nil : coerced)
      end
    end

    def repeat_until=(value)
      @repeat_until = case value
                      when nil, '' then nil
                      when Time then value.utc
                      when String then parse_until(value)
                      end
    end

    def to_rrule
      {
        'FREQ' => frequency,
        'INTERVAL' => interval,
        'COUNT' => non_blank(count),
        'UNTIL' => format_until(repeat_until),
        'BYDAY' => join_list(by_day),
        'BYMONTHDAY' => join_list(by_month_day),
        'BYMONTH' => join_list(month_of_year),
        'BYHOUR' => join_list(hour_of_day),
        'BYMINUTE' => join_list(minute_of_hour),
        'BYSECOND' => join_list(second_of_minute),
        'BYYEARDAY' => join_list(day_of_year),
        'BYWEEKNO' => join_list(week_of_year),
        'BYSETPOS' => join_list(by_set_pos),
        'WKST' => non_blank(week_start)
      }.filter_map { |k, v| "#{k}=#{v}" unless v.nil? }.join(';')
    end

    def monthly_option
      return unless frequency == 'MONTHLY'
      return 'NTH_DAY' if by_set_pos&.any? && by_day&.any?

      'DATE' if by_month_day&.any?
    end

    def by_month_day_option?
      monthly_option == 'DATE'
    end

    def by_set_pos_option?
      monthly_option == 'NTH_DAY'
    end

    def <=>(other)
      return super unless other.is_a?(self.class)

      FREQ_ORDER[frequency] <=> FREQ_ORDER[other.frequency]
    end

    private

    def non_blank(value)
      value unless value.nil? || value.to_s.strip.empty?
    end

    def join_list(array)
      non_blank(array&.join(','))
    end

    def format_until(time)
      time&.utc&.strftime('%Y%m%dT%H%M%SZ')
    end

    def parse_until(value)
      return unless (match = non_blank(value)&.match(UNTIL_PATTERN))

      Time.utc(match[:Y], match[:m], match[:d], match[:H], match[:M], match[:S])
    end
  end
end
