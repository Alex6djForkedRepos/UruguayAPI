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

    def parse_events(html)
      doc = Nokogiri::HTML(html)
      doc.css('div.eventItem').map do |item|
        {
          date: item.css('.info-wrapper .info .date').text.strip,
          thumbnail: item.css('.thumb img').attr('src')&.value,
          artist: item.css('.info-wrapper .info .h3').text.strip,
          concert: item.css('.info-wrapper .info .h4').text.strip,
          more_info: item.css('.info-wrapper .buttons a')[0]&.attr('href'),
          buy_tickets: item.css('.info-wrapper .buttons a.tickets')[0]&.attr('href'),
        }
      end
    end
  end
end
