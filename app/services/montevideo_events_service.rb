# frozen_string_literal: true

# Servicio de eventos de la Intendencia de Montevideo.
#
# Scrapea el portal de eventos culturales de Montevideo, que organiza las
# actividades por categoría (música, deportes, gastronomía, etc.).
#
# Categorías válidas: artes-escenicas, gastronomia, institucional, audiovisual,
# literatura, paseos, recreacion, musica, deportes, carnaval, artes-visuales
#
# Fuente: https://eventos.montevideo.gub.uy
class MontevideoEventsService
  BASE_URL = 'https://eventos.montevideo.gub.uy'

  VALID_CATEGORIES = %w[
    artes-escenicas gastronomia institucional audiovisual literatura
    paseos recreacion musica deportes carnaval artes-visuales
  ].freeze

  class << self
    def fetch_by_category(category)
      return nil unless valid_category?(category)

      events = []
      page = 0
      loop do
        url = "#{BASE_URL}/categoria/#{category}?page=#{page}"
        doc = Nokogiri::HTML(HTTParty.get(url).body)
        articles = doc.css('article.node--type-actividad')
        break if articles.empty?

        events += articles.map { |article| extract_data(article) }
        page += 1
      end

      events
    end

    def fetch_all
      VALID_CATEGORIES.each_with_object({}) do |category, result|
        result[category.to_sym] = fetch_by_category(category)
      end
    end

    def valid_category?(category)
      VALID_CATEGORIES.include?(category)
    end

    private

    def extract_data(article)
      title_link = article.css('.field--name-title a').first
      dates = article.css('.field--name-field-fechas time')

      {
        source: 'Eventos Montevideo',
        source_url: BASE_URL,
        title: title_link&.text&.strip,
        venue: clean_text(article.css('.field--name-field-donde')),
        date: clean_text(article.css('.field--name-field-resumen')),
        start_date: dates[0]&.[]('datetime'),
        end_date: dates[1]&.[]('datetime'),
        category: article.css('.field--name-field-categoria-listado a').text.strip.presence,
        thumbnail: absolute_url(article.css('.field--name-field-imagen-miniatura-listados img').first&.[]('src')),
        event_link: absolute_url(title_link&.[]('href').to_s),
      }
    end

    def clean_text(node)
      node.text.gsub(/\s+/, ' ').strip.presence
    end

    def absolute_url(path)
      return nil if path.nil? || path.empty?

      path.start_with?('http') ? path : "#{BASE_URL}#{path}"
    end
  end
end
