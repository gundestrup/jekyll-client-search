#!/usr/bin/env ruby
# frozen_string_literal: true

# Downloads 40 Wikipedia articles and converts them to Jekyll fixture posts
# for search testing. Each post includes source attribution, download date,
# and license information in its frontmatter.
#
# Wikipedia content is licensed under CC BY-SA 3.0:
#   https://creativecommons.org/licenses/by-sa/3.0/
#
# Usage:
#   ruby spec/fixtures/download_wikipedia.rb
#
# Articles are selected with deliberate cross-topic overlap to test search
# discrimination:
#   - Arctic/cold/ice (8 articles)
#   - Mountains/climbing (8 articles)
#   - Photography/optics (8 articles)
#   - Food/cooking (8 articles)
#   - Technology/electronics (8 articles)

require "net/http"
require "json"
require "date"
require "fileutils"
require "cgi"

POSTS_DIR = File.expand_path("_posts", __dir__)
FileUtils.mkdir_p(POSTS_DIR)

# Remove old Wikipedia posts
Dir.glob(File.join(POSTS_DIR, "wikipedia-*.md")).each { |f| File.delete(f) }

DOWNLOAD_DATE = Date.today.strftime("%Y-%m-%d")
LICENSE = "CC BY-SA 3.0"
SOURCE = "Wikipedia — The Free Encyclopedia"
SOURCE_URL = "https://en.wikipedia.org"

# [title, category, tags]
ARTICLES = [
  # Arctic / cold / ice
  ["Glacier", "geography", %w[ice cold arctic nature]],
  ["Iceberg", "geography", %w[ice cold arctic ocean]],
  ["Sea ice", "oceanography", %w[ice cold arctic ocean]],
  ["Permafrost", "geography", %w[cold arctic ground climate]],
  ["Tundra", "ecology", %w[cold arctic vegetation climate]],
  ["Arctic Circle", "geography", %w[arctic cold geography]],
  ["Polar climate", "climatology", %w[cold arctic climate weather]],
  ["Aurora", "astronomy", %w[arctic light sky nature]],
  # Mountains / climbing
  ["Mountaineering", "sports", %w[climbing mountain adventure cold]],
  ["Rock climbing", "sports", %w[climbing rock adventure gear]],
  ["Ice climbing", "sports", %w[ice climbing cold adventure gear]],
  ["Mountain", "geography", %w[mountain nature geography]],
  ["Altitude sickness", "medicine", %w[mountain health altitude]],
  ["Alpine climate", "climatology", %w[mountain cold climate weather]],
  ["Carabiner", "climbing", %w[climbing gear safety metal]],
  ["Belay device", "climbing", %w[climbing gear safety rope]],
  # Photography / optics
  ["Photography", "arts", %w[photography light art image]],
  ["Digital photography", "technology", %w[photography digital camera technology]],
  ["Camera lens", "optics", %w[photography lens optics camera]],
  ["Image sensor", "technology", %w[photography sensor digital camera]],
  ["Astrophotography", "astronomy", %w[photography night astronomy light]],
  ["Landscape photography", "arts", %w[photography landscape nature light]],
  ["Aperture", "optics", %w[photography lens optics light]],
  ["Depth of field", "optics", %w[photography lens optics focus]],
  # Food / cooking
  ["Italian cuisine", "food", %w[food cooking italian family]],
  ["French cuisine", "food", %w[food cooking french technique]],
  ["Japanese cuisine", "food", %w[food cooking japanese technique]],
  ["Bread", "food", %w[food cooking bread baking family]],
  ["Fermentation in food processing", "food", %w[food cooking fermentation technique]],
  ["Chocolate", "food", %w[food cooking chocolate sweet]],
  ["Pasta", "food", %w[food cooking italian pasta]],
  ["Sourdough", "food", %w[food cooking bread fermentation]],
  # Technology / electronics
  ["Lithium-ion battery", "technology", %w[technology battery electronics cold]],
  ["Solar panel", "technology", %w[technology solar power electronics]],
  ["Global Positioning System", "technology", %w[technology gps satellite navigation]],
  ["Satellite phone", "technology", %w[technology satellite communication gear]],
  ["Extreme cold weather clothing", "technology", %w[cold clothing gear technology]],
  ["Digital single-lens reflex camera", "technology", %w[photography camera digital technology]],
  ["Mirrorless camera", "technology", %w[photography camera digital technology]],
  ["Tripod", "photography", %w[photography gear camera support]]
].freeze

def fetch_wikipedia_extract(title)
  api_url = "https://en.wikipedia.org/w/api.php?action=query&titles=#{CGI.escape(title)}" \
            "&prop=extracts&explaintext=1&format=json&redirects=1"
  uri = URI(api_url)

  3.times do |attempt|
    response = Net::HTTP.get_response(uri)
    if response.is_a?(Net::HTTPSuccess)
      data = JSON.parse(response.body)
      pages = data.dig("query", "pages")
      return nil unless pages

      page = pages.values.first
      extract = page["extract"]
      return nil unless extract

      # Truncate to ~2000 words for manageable test size
      words = extract.split
      if words.length > 2500
        extract = words.take(2500).join(" ") + "..."
      end

      return {
        title: page["title"],
        extract: extract,
        url: "#{SOURCE_URL}/wiki/#{page['title'].tr(' ', '_')}"
      }
    elsif response.code == "429" || response.code == "503"
      sleep(3 * (attempt + 1))
      next
    else
      return nil
    end
  end
  nil
end

def write_post(article, index, fetch_result)
  title, category, tags = article
  date = Date.new(2026, 1, 1) + index
  slug = title.downcase.gsub(/[^a-z0-9]+/, "-").gsub(/^-|-$/, "")
  filename = "#{date.strftime('%Y-%m-%d')}-wikipedia-#{slug}.md"
  filepath = File.join(POSTS_DIR, filename)

  frontmatter = {
    "title" => fetch_result[:title],
    "categories" => [category],
    "tags" => tags,
    "source" => SOURCE,
    "source_url" => fetch_result[:url],
    "download_date" => DOWNLOAD_DATE,
    "license" => LICENSE
  }

  yaml = frontmatter.map do |k, v|
    if v.is_a?(Array)
      "#{k}:\n" + v.map { |item| "  - #{item}" }.join("\n")
    else
      "#{k}: #{v.to_s.inspect}"
    end
  end.join("\n")
  body = fetch_result[:extract]

  File.write(filepath, "---\n#{yaml}\n---\n\n#{body}\n")
  filepath
end

generated = []
skipped = []

ARTICLES.each_with_index do |article, index|
  title = article[0]
  print "Fetching: #{title}... "
  result = fetch_wikipedia_extract(title)
  if result
    path = write_post(article, index, result)
    words = File.read(path).split.length
    generated << { title: title, path: path, words: words }
    puts "#{words} words"
  else
    skipped << title
    puts "FAILED"
  end
  sleep 2 # Be polite to the API
end

puts "\nGenerated #{generated.length} Wikipedia posts"
puts "Skipped: #{skipped.join(', ')}" unless skipped.empty?
total = generated.sum { |g| g[:words] }
puts "Total words: #{total}"
puts "Average: #{total / [generated.length, 1].max} words/post"
