# frozen_string_literal: true

# Source: https://redtickets.uy/busqueda?,*,0,0
class RedticketsService
  BASE_URL = 'https://redtickets.uy'
  MAX_PAGES = 50
  SPANISH_MONTHS = %w[_ enero febrero marzo abril mayo junio julio agosto
                      septiembre octubre noviembre diciembre].freeze
  RECURRING_HINTS = [
    'todos los d', 'todo el a', 'lunes a', 'martes a', 'miércoles a',
    'miercoles a', 'jueves a', 'viernes a', 'de lunes', 'paga la reserva'
  ].freeze

  class << self
    def fetch_events(date: today, period: 'daily', details: false)
      dates = dates_for(date, period)
      events = scrape_all
      events = events.map { |e| enrich(e) } if details

      if dates.one?
        filter_for_date(events, dates.first)
      else
        dates.each_with_object({}) do |d, result|
          result[d.strftime('%Y-%m-%d')] = filter_for_date(events, d)
        end
      end
    end

    private

    def today
      Time.now.in_time_zone('Montevideo').to_date
    end

    def dates_for(date, period)
      case period
      when 'weekly'  then (date..date + 6).to_a
      when 'monthly' then (date..date + 29).to_a
      else [date]
      end
    end

    def scrape_all
      events = []
      MAX_PAGES.times do |page|
        html = HTTParty.get("#{BASE_URL}/busqueda?,*,0,#{page}").body
        state = parse_gxstate(html)
        break unless state

        events.concat(state['vSDTPLAINEVTCOLLECTION'].to_a.map { |e| build_event(e) })
        total = state['W0026vRESULTCOUNT'].to_i
        break if events.size >= total
      end
      events
    end

    def parse_gxstate(html)
      match = html.match(%r{name="GXState" value='(.+?)'\s*/?>}m)
      return nil unless match

      JSON.parse(CGI.unescapeHTML(match[1]))
    rescue JSON::ParserError
      nil
    end

    def build_event(raw)
      link = raw['Link'].to_s
      info = link.start_with?('http') ? link : "#{BASE_URL}#{link}"
      {
        source: 'redtickets',
        id: raw['Id'], name: raw['Title'], date: raw['Date'],
        venue: raw['Address'], description: strip_html(raw['Description']),
        img: raw['Image'], info: info, category: raw['Category']
      }
    end

    def strip_html(html)
      html && Nokogiri::HTML.fragment(html).text.gsub(/\s+/, ' ').strip
    end

    def filter_for_date(events, date)
      events.select { |e| matches_date?(e, date) }
    end

    def matches_date?(event, date)
      return any_date_in_range?(event[:dates], date, date) if event[:dates].is_a?(Array)

      text = event[:date].to_s.downcase
      return true if RECURRING_HINTS.any? { |h| text.include?(h) }

      parse_spanish_date(text, date.year) == date
    end

    def parse_spanish_date(text, year)
      match = text.match(/(\d{1,2})\s+de\s+([a-záéíóú]+)/i)
      month = SPANISH_MONTHS.index(match[2].downcase.tr('áéíóú', 'aeiou').sub(/^setiembre$/, 'septiembre')) if match
      return nil unless month&.positive?

      Date.new(year, month, match[1].to_i)
    rescue Date::Error
      nil
    end

    def any_date_in_range?(dates, from, to)
      dates.any? do |d|
        (from..to).cover?(Date.parse(d))
      rescue Date::Error, TypeError
        false
      end
    end

    def enrich(event)
      html = HTTParty.get(event[:info]).body
      state = parse_gxstate(html)
      return event unless state

      event.merge(dates: parse_allowed_dates(state))
    end

    def parse_allowed_dates(state)
      JSON.parse(state['W0013UCPICKEVENTDATES1_alloweddates'].to_s)
    rescue JSON::ParserError
      []
    end
  end
end
