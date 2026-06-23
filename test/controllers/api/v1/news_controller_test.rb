require "test_helper"
require "webmock/minitest"

class Api::V1::NewsControllerTest < ActionDispatch::IntegrationTest
  ARTICLE_URL_1 = "https://www.montevideo.com.uy/Test/Articulo-uno-uc001"
  ARTICLE_URL_2 = "https://www.montevideo.com.uy/Test/Articulo-dos-uc002"

  RANKING_HTML = <<~HTML
    <html><body>
      <h2 class="title"><a href="#{ARTICLE_URL_1}">Título de prueba 1</a></h2>
      <h2 class="title"><a href="#{ARTICLE_URL_2}">Título de prueba 2</a></h2>
    </body></html>
  HTML

  ARTICLE_HTML_WITH_IMG = <<~HTML
    <html><body>
      <div class="foto-ppal hidden-xs"><img src="https://imagenes.montevideo.com.uy/foto.jpg"></div>
    </body></html>
  HTML

  ARTICLE_HTML_WITH_GALLERY = <<~HTML
    <html><body>
      <div id="gallery-1"><img src="https://imagenes.montevideo.com.uy/gallery.jpg"></div>
    </body></html>
  HTML

  ARTICLE_HTML_NO_IMG = "<html><body><p>Sin imagen</p></body></html>"

  setup do
    Api::V1::NewsController::SOURCES.each do |source|
      stub_request(:get, source[:url]).to_return(body: RANKING_HTML, status: 200)
    end

    stub_request(:get, ARTICLE_URL_1).to_return(body: ARTICLE_HTML_WITH_IMG, status: 200)
    stub_request(:get, ARTICLE_URL_2).to_return(body: ARTICLE_HTML_WITH_IMG, status: 200)
  end

  test "returns 200" do
    get api_v1_news_headlines_path
    assert_response :success
  end

  test "returns all four sources" do
    get api_v1_news_headlines_path
    json = JSON.parse(response.body)
    assert_equal %w[Noticias Deportes Pantallazo Tecnología], json.map { |s| s["source"] }
  end

  test "each source contains headlines" do
    get api_v1_news_headlines_path
    json = JSON.parse(response.body)
    json.each do |source|
      assert source["headlines"].is_a?(Array), "#{source["source"]} should have a headlines array"
      assert source["headlines"].length > 0, "#{source["source"]} should have at least one headline"
    end
  end

  test "headlines have title, href and img" do
    get api_v1_news_headlines_path
    json = JSON.parse(response.body)
    json.each do |source|
      headline = source["headlines"].first
      assert headline.key?("title"), "headline missing title"
      assert headline.key?("href"),  "headline missing href"
      assert headline.key?("img"),   "headline missing img"
    end
  end

  test "headline title is stripped" do
    get api_v1_news_headlines_path
    json = JSON.parse(response.body)
    assert_equal "Título de prueba 1", json.first["headlines"].first["title"]
  end

  test "headline href is preserved" do
    get api_v1_news_headlines_path
    json = JSON.parse(response.body)
    assert_equal ARTICLE_URL_1, json.first["headlines"].first["href"]
  end

  test "headline img is fetched from foto-ppal" do
    get api_v1_news_headlines_path
    json = JSON.parse(response.body)
    assert_equal "https://imagenes.montevideo.com.uy/foto.jpg", json.first["headlines"].first["img"]
  end

  test "headline img falls back to gallery-1" do
    stub_request(:get, ARTICLE_URL_1).to_return(body: ARTICLE_HTML_WITH_GALLERY, status: 200)
    stub_request(:get, ARTICLE_URL_2).to_return(body: ARTICLE_HTML_WITH_GALLERY, status: 200)

    get api_v1_news_headlines_path
    json = JSON.parse(response.body)
    assert_equal "https://imagenes.montevideo.com.uy/gallery.jpg", json.first["headlines"].first["img"]
  end

  test "headline img is empty string when no image found" do
    stub_request(:get, ARTICLE_URL_1).to_return(body: ARTICLE_HTML_NO_IMG, status: 200)
    stub_request(:get, ARTICLE_URL_2).to_return(body: ARTICLE_HTML_NO_IMG, status: 200)

    get api_v1_news_headlines_path
    json = JSON.parse(response.body)
    assert_equal "", json.first["headlines"].first["img"]
  end
end
