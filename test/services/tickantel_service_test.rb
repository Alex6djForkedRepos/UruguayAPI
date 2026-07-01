# frozen_string_literal: true

require "test_helper"
require "minitest/mock"

class TickantelServiceTest < ActiveSupport::TestCase
  test "enriches each recurring event once across a weekly range, not once per day" do
    monday = Date.new(2026, 7, 6)
    show_a = { source: 'Tickantel', title: 'Show A', event_link: 'https://tickantel.com.uy/inicio/espectaculo/a' }
    show_b = { source: 'Tickantel', title: 'Show B', event_link: 'https://tickantel.com.uy/inicio/espectaculo/b' }

    fetch_calls = Concurrent::Array.new
    enrich_calls = Concurrent::Array.new

    TickantelService.stub(:fetch_for_date, lambda { |date|
      fetch_calls << date
      date == monday ? [show_a] : [show_a, show_b]
    }) do
      TickantelService.stub(:fetch_show, lambda { |link|
        enrich_calls << link
        { description: "desc for #{link}" }
      }) do
        result = TickantelService.fetch_events(date: monday, period: 'weekly')

        assert_equal 7, fetch_calls.size
        assert_equal 2, enrich_calls.uniq.size
        assert_equal 'desc for https://tickantel.com.uy/inicio/espectaculo/a', result['2026-07-06'].first[:description]
        assert_equal 2, result['2026-07-07'].size
      end
    end
  end

  test "a single day failing to scrape does not blank out the rest of the week" do
    monday = Date.new(2026, 7, 6)
    show = { source: 'Tickantel', title: 'Show A', event_link: 'https://tickantel.com.uy/inicio/espectaculo/a' }

    call_count = Concurrent::AtomicFixnum.new(0)
    TickantelService.stub(:fetch_for_date, lambda { |_date|
      raise 'boom' if call_count.increment == 3

      [show]
    }) do
      TickantelService.stub(:fetch_show, ->(_link) { {} }) do
        result = TickantelService.fetch_events(date: monday, period: 'weekly')

        assert_equal 7, result.size
        assert(result.values.any?(&:empty?), 'expected the failed day to fall back to an empty list')
        assert(result.values.any? { |events| events.any? }, 'expected the other days to still have events')
      end
    end
  end

  test "daily period returns a flat enriched array" do
    day = Date.new(2026, 7, 6)
    show = { source: 'Tickantel', title: 'Show A', event_link: 'https://tickantel.com.uy/inicio/espectaculo/a' }

    TickantelService.stub(:fetch_for_date, ->(_date) { [show] }) do
      TickantelService.stub(:fetch_show, ->(_link) { { description: 'desc' } }) do
        result = TickantelService.fetch_events(date: day, period: 'daily')

        assert_equal 1, result.size
        assert_equal 'desc', result.first[:description]
      end
    end
  end
end
