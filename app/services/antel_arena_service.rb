# frozen_string_literal: true

# Servicio de eventos del Antel Arena.
#
# Scrapea el listado de eventos del Antel Arena, incluyendo los cargados
# vía AJAX (paginación con offset incremental).
#
# Fuente: https://www.antelarena.com.uy/events
class AntelArenaService
  BASE_URL = 'https://www.antelarena.com.uy'

  AJAX_HEADERS = {
    'accept' => 'application/json, text/javascript, */*; q=0.01',
    'referer' => "#{BASE_URL}/events",
    'user-agent' => 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/147.0.0.0 Safari/537.36',
    'x-requested-with' => 'XMLHttpRequest',
  }.freeze

  PAGE_SIZE = 12

  class << self
    def fetch_events
      response = HTTParty.get("#{BASE_URL}/events")
      events_data = parse_events(response.body)

      offset = PAGE_SIZE
      loop do
        url = "#{BASE_URL}/events/events_ajax/#{offset}?category=0&venue=0&team=0&exclude=&per_page=#{PAGE_SIZE}&came_from_page=event-list-page"
        resp = HTTParty.get(url, headers: AJAX_HEADERS)
        body = resp.body.to_s.strip
        break if body.empty? || body == '""'

        html = JSON.parse(body) rescue body
        batch = parse_events(html)
        break if batch.empty?

        events_data += batch
        offset += PAGE_SIZE
      end

      events_data
    end

    private

    def fetch_details(url)
      return {} unless url&.start_with?(BASE_URL)

      doc = Nokogiri::HTML(HTTParty.get(url).body)

      info = doc.css('.eventDetailList .item').each_with_object({}) do |item, h|
        label = item.css('div').text.strip
        value = item.css('span').first&.text&.strip
        h[label] = value
      end

      {
        date: info['fecha'],
        time: info['hora'],
        doors_open: info['las puertas se abrirán'],
        price: info['precio de las entradas'],
        description: doc.css('.event_description').text.gsub(/\s+/, ' ').strip.presence,
      }
    end

    def parse_events(html)
      doc = Nokogiri::HTML(html)
      doc.css('div.eventItem').map do |item|
        artist     = item.css('.info-wrapper .info .h3').text.strip
        concert    = item.css('.info-wrapper .info .h4').text.strip
        event_link = item.css('.info-wrapper .buttons a')[1]&.attr('href')
        {
          source: 'Antel Arena',
          source_url: BASE_URL,
          title: [concert, artist].reject(&:empty?).join(' - '),
          thumbnail: item.css('.thumb img').attr('src')&.value,
          event_link: event_link,
          buy_tickets: item.css('.info-wrapper .buttons a.tickets')[0]&.attr('href'),
        }.merge(fetch_details(event_link))
      end
    end
  end
end
