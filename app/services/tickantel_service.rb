# frozen_string_literal: true

# Source: https://tickantel.com.uy/inicio/calendario
class TickantelService
  BASE_URL = 'https://tickantel.com.uy'

  class << self
    def fetch_events(date: Date.today, period: 'daily')
      dates = dates_for(date, period)
      return enrich(fetch_for_date(dates.first)) if dates.one?

      # El mismo espectáculo suele repetirse todos los días de la semana: se
      # piden los stubs de cada día en paralelo y se enriquece cada evento
      # único UNA sola vez (antes se re-scrapeaba y re-enriquecía por día,
      # 7 veces el mismo trabajo), lo que superaba el idle timeout de la
      # edge function.
      stubs_by_date = fetch_stubs_concurrently(dates)
      enriched_by_link = enrich_unique(stubs_by_date.values.flatten)

      stubs_by_date.transform_values do |events|
        events.map { |e| e.merge(enriched_by_link[e[:event_link]] || {}) }
      end
    end

    private

    def dates_for(date, period)
      case period
      when 'weekly'  then (date..date + 6).to_a
      when 'monthly' then (date..date + 29).to_a
      else [date]
      end
    end

    def fetch_stubs_concurrently(dates)
      futures = dates.map { |d| [d, Concurrent::Future.execute { fetch_for_date(d) }] }
      futures.each_with_object({}) { |(d, future), result| result[d.strftime('%Y-%m-%d')] = future.value || [] }
    end

    def enrich(events)
      enriched_by_link = enrich_unique(events)
      events.map { |e| e.merge(enriched_by_link[e[:event_link]] || {}) }
    end

    def enrich_unique(events)
      futures = events.uniq { |e| e[:event_link] }.map { |e| [e[:event_link], Concurrent::Future.execute { fetch_show(e[:event_link]) }] }
      futures.each_with_object({}) { |(link, future), result| result[link] = future.value }
    end

    def fetch_for_date(date)
      cookie = open_session(date)
      return [] unless cookie

      events = []
      loop do
        batch = fetch_more(cookie)
        break if batch.size <= events.size

        events = batch
      end

      events
    end

    def open_session(date)
      response = HTTParty.get("#{BASE_URL}/inicio/calendario?fecha=#{date.strftime('%d-%m-%Y')}")
      response.request.options[:headers]['Cookie']
    end

    def fetch_more(cookie)
      response = HTTParty.get("#{BASE_URL}/inicio/calendario?0-1.IBehaviorListener.0-cargarMasResultadosPanel", headers: {
        'Cookie' => cookie,
        'Wicket-Ajax' => 'true',
        'Wicket-Ajax-BaseURL' => 'calendario?0',
      })
      parse_events(response.body)
    end

    def parse_events(xml)
      items = Nokogiri::XML(xml).css('component').flat_map { |c| Nokogiri::HTML(c.text).css('div.item') }
      items.filter_map do |item|
        href = item.css('a').first&.attr('href')
        next unless href&.include?('espectaculo')

        {
          source: 'Tickantel',
          source_url: BASE_URL,
          title: item.css('.title .span-block').first&.text&.strip,
          date: item.css('.auto-pf-date').text.gsub(/&nbsp;?/, ' ').gsub(/\s+/, ' ').strip,
          venue: item.css('p:last-of-type span').map(&:text).map(&:strip).reject(&:empty?).join(' - '),
          thumbnail: item.css('figure img').first&.attr('src'),
          event_link: "#{BASE_URL}/inicio/#{href.delete_prefix('./')}",
        }
      end
    end

    def fetch_show(link)
      ld = Nokogiri::HTML(HTTParty.get(link).body)
                   .css('script[type="application/ld+json"]')
                   .filter_map { |s| JSON.parse(s.text) rescue nil }
                   .find { |j| j['@type'] == 'Event' }

      return {} unless ld

      offers = ld['offers'] || {}
      {
        title: ld['name'],
        description: ld['description'],
        thumbnail: Array(ld['image']).first,
        venue: ld.dig('location', 'name'),
        performer: ld.dig('performer', 'name'),
        start_date: ld['startDate'],
        end_date: ld['endDate'],
        next_function: offers['availabilityStarts'],
        price_low: offers['lowPrice'],
        price_high: offers['highPrice'],
        price_currency: offers['priceCurrency'],
      }
    end
  end
end
