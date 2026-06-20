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

      first_doc = fetch_doc(category, 0)
      events = parse_articles(first_doc)
      last = last_page(first_doc)
      return events if last.zero?

      events + (1..last).map { |page| Thread.new(page) { |p| parse_articles(fetch_doc(category, p)) } }.flat_map(&:value)
    end

    def fetch_all
      VALID_CATEGORIES.map { |category| Thread.new(category) { |c| [c.to_sym, fetch_by_category(c)] } }.map(&:value).to_h
    end

    def valid_category?(category)
      VALID_CATEGORIES.include?(category)
    end

    private

    def fetch_doc(category, page)
      Nokogiri::HTML(HTTParty.get("#{BASE_URL}/categoria/#{category}?page=#{page}").body)
    end

    def parse_articles(doc)
      doc.css('article.node--type-actividad').map { |article| extract_data(article) }
    end

    def last_page(doc)
      href = doc.css('a[title="Ir a la última página"]').first&.[]('href')
      href && href.match(/page=(\d+)/) ? Regexp.last_match(1).to_i : 0
    end

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
