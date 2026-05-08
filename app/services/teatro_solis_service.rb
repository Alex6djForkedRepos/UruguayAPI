# frozen_string_literal: true

# Source: https://www.teatrosolis.org.uy/acategoriaperiodo.aspx?8,YYYYMMDD,YYYYMMDD,0
class TeatroSolisService
  BASE_URL = 'https://www.teatrosolis.org.uy'
  EVENTS_PATH = '/acategoriaperiodo.aspx'
  MAX_PAGES = 10
  SPANISH_MONTHS = %w[_ enero febrero marzo abril mayo junio julio agosto
                      septiembre octubre noviembre diciembre].freeze

  class << self
    def fetch_events(date: today, period: 'daily')
      dates = dates_for(date, period)
      events = scrape_events(dates.first, dates.last)
      return events if dates.one?

      dates.each_with_object({}) do |d, result|
        result[d.strftime('%Y-%m-%d')] = events.select { |e| event_on_date?(e, d) }
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

    def scrape_events(from, to)
      from_str = from.strftime('%Y%m%d')
      to_str   = to.strftime('%Y%m%d')
      events   = []
      MAX_PAGES.times do |page|
        cards = parse_cards(fetch_html(from_str, to_str, page))
        events.concat(cards)
        break if cards.size < 10
      end
      events
    end

    def fetch_html(from_str, to_str, page)
      HTTParty.get("#{BASE_URL}#{EVENTS_PATH}?8,#{from_str},#{to_str},#{page}").body
    end

    def parse_cards(html)
      Nokogiri::HTML(html).css('.block-card').map { |card| build_event(card) }
    end

    def build_event(card)
      event_link = absolute_url(attr_at(card, 'a.picture', 'href'))
      {
        source: 'Teatro Solís',
        source_url: BASE_URL,
        title: text_at(card, 'h2 a'),
        date: text_at(card, 'li.icdia'),
        venue: text_at(card, 'li.icsala'),
        category: text_at(card, 'li.icgenero'),
        thumbnail: absolute_url(attr_at(card, 'img', 'src')),
        description: fetch_description(event_link),
        buy_tickets: attr_at(card, 'li.icticket a', 'href'),
        event_link: event_link,
      }
    end

    def fetch_description(url)
      return nil unless url&.start_with?(BASE_URL)

      doc = Nokogiri::HTML(HTTParty.get(url).body)
      doc.css('.content').text.gsub(/\s+/, ' ').strip.presence
    end

    def text_at(node, selector)
      node.at_css(selector)&.text&.strip
    end

    def attr_at(node, selector, attribute)
      node.at_css(selector)&.[](attribute).to_s
    end

    def absolute_url(path)
      path.start_with?('http') ? path : "#{BASE_URL}#{path}"
    end

    def event_on_date?(event, date)
      parse_event_dates(event[:date].to_s, date.year).include?(date)
    end

    def parse_event_dates(text, year)
      month = extract_month(text)
      return [] unless month&.positive?

      days_part = text[0, text.index('de')].to_s
      days_part.scan(/\d+/).filter_map do |d|
        Date.new(year, month, d.to_i)
      rescue Date::Error
        nil
      end
    end

    def extract_month(text)
      match = text.match(/de\s+([a-záéíóú]+)/i)
      return unless match

      name = match[1].downcase.tr('áéíóú', 'aeiou').sub(/^setiembre$/, 'septiembre')
      SPANISH_MONTHS.index(name)
    end
  end
end
