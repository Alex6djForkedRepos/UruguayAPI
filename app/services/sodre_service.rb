# frozen_string_literal: true

# Source: https://sodre.gub.uy/espectaculos/calendario/
# Events are loaded via WordPress AJAX — requires a nonce fetched from the page first.
class SodreService
  BASE_URL    = 'https://sodre.gub.uy'
  CALENDAR_PAGE = '/espectaculos/calendario/'
  AJAX_URL    = 'https://sodre.gub.uy/espectaculos/wp-admin/admin-ajax.php'

  class << self
    def fetch_events(date: today, period: 'daily')
      dates  = dates_for(date, period)
      nonce  = fetch_nonce(dates.first)
      return [] unless nonce

      all_events = fetch_ajax_events(nonce, dates.first, dates.last + 1)
      return all_events if dates.one?

      dates.each_with_object({}) do |d, result|
        result[d.strftime('%Y-%m-%d')] = all_events.select { |e| e[:start].nil? || event_on_date?(e, d) }
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

    def fetch_nonce(date)
      url  = "#{BASE_URL}#{CALENDAR_PAGE}?from=#{date.strftime('%Y-%m-%d')}"
      html = HTTParty.get(url).body
      html.match(/"nonce":"([^"]+)"/)&.[](1)
    end

    def fetch_ajax_events(nonce, from, to)
      response = HTTParty.get(AJAX_URL, query: {
        action: 'Calendar',
        nonce:  nonce,
        s:      '',
        from:   from.strftime('%Y-%m-%d'),
        to:     to.strftime('%Y-%m-%d'),
      })
      data = JSON.parse(response.body)
      return [] unless data['success']

      data['data'].filter_map { |e| build_event(e) }
    end

    def build_event(raw)
      props = raw['extendedProps'] || {}
      {
        source:      'SODRE',
        source_url:  BASE_URL,
        title:       raw['title'],
        date:        format_date(props['fecha_visible']),
        start:       raw['start'],
        end:         raw['end'],
        category:    ensemble_names(props['elencoEstablesData']),
        thumbnail:   valid_thumbnail(props['foto_miniatura']),
        description: props['resumen']&.strip.presence,
        buy_tickets: props['enlace_de_compra'].presence,
        event_link:  raw['url'],
      }
    end

    def event_on_date?(event, date)
      start_str = event[:start]
      return false unless start_str

      Date.parse(start_str) == date
    rescue Date::Error
      false
    end

    def ensemble_names(data)
      return nil unless data.is_a?(Array)

      data.map { |e| e['name'] }.compact.join(', ').presence
    end

    def valid_thumbnail(value)
      value.is_a?(String) && value.start_with?('http') ? value : nil
    end

    def format_date(text)
      text&.gsub(/\r\n/, ' / ')&.strip.presence
    end
  end
end
