class Api::V1::NewsController < ApplicationController
  SOURCES = [
    { name: 'Noticias', url: 'https://www.montevideo.com.uy/anranking.aspx?0,1798,1,0,D' },
    { name: 'Deportes', url: 'https://www.montevideo.com.uy/anranking.aspx?0,1975,1,94,H' },
    { name: 'Pantallazo', url: 'https://www.montevideo.com.uy/anranking.aspx?0,1821,1,756,H' },
    { name: 'Tecnología', url: 'https://www.montevideo.com.uy/acategoria.aspx?412' }
  ].freeze

  def headlines
    data = SOURCES.map { |source| scrape_source(source) }
    render json: data
  end

  private

  def scrape_source(source)
    response = HTTParty.get(source[:url])
    doc = Nokogiri::HTML(response.body)

    headlines = doc.css('h2.title').map do |title|
      anchor = title.css('a').first
      { href: anchor['href'], title: title.text.strip }
    end

    headlines.each do |headline|
      article_response = HTTParty.get(headline[:href])
      article_doc = Nokogiri::HTML(article_response.body)
      headline[:img] = article_doc.css('.foto-ppal.hidden-xs img').first&.[]('src') ||
                       article_doc.css('#gallery-1 img').first&.[]('src') ||
                       article_doc.at('meta[property="og:image"]')&.[]('content') ||
                       ''
    end

    { source: source[:name], headlines: headlines }
  end
end
