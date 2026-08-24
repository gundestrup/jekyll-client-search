#!/usr/bin/env ruby
# frozen_string_literal: true

# Downloads 40 arXiv papers and converts them to Jekyll fixture posts
# for search testing. Each post includes source attribution, download date,
# and license information in its frontmatter.
#
# arXiv papers are typically licensed under arXiv's non-exclusive license
# or CC BY / CC BY-NC. The specific license is recorded per-paper.
#
# Usage:
#   ruby spec/fixtures/download_arxiv.rb
#
# Papers are selected from 5 CS/AI subfields with deliberate overlap:
#   - Information retrieval / search (8 papers)
#   - NLP / embeddings / language models (8 papers)
#   - Computer vision / image retrieval (8 papers)
#   - Recommendation systems (8 papers)
#   - Knowledge graphs / semantic web (8 papers)
#
# These fields share vocabulary (embeddings, vectors, similarity, retrieval)
# but differ in application, making them ideal for testing semantic search
# discrimination between closely related topics.

require "net/http"
require "rexml/document"
require "date"
require "fileutils"
require "open3"
require "tempfile"

POSTS_DIR = File.expand_path("_posts", __dir__)
FileUtils.mkdir_p(POSTS_DIR)

# Remove old arXiv posts
Dir.glob(File.join(POSTS_DIR, "arxiv-*.md")).each { |f| File.delete(f) }

DOWNLOAD_DATE = Date.today.strftime("%Y-%m-%d")
SOURCE = "arXiv.org"
SOURCE_URL = "https://arxiv.org"

# arXiv category queries — each returns recent papers in that subfield
QUERIES = [
  { category: "information-retrieval", tags: %w[search retrieval indexing query], arxiv_cat: "cs.IR", max: 8 },
  { category: "natural-language-processing", tags: %w[nlp embeddings language model], arxiv_cat: "cs.CL", max: 8 },
  { category: "computer-vision", tags: %w[vision image retrieval neural], arxiv_cat: "cs.CV", max: 8 },
  { category: "recommendation-systems", tags: %w[recommendation retrieval ranking user], arxiv_cat: "cs.IR", max: 8 },
  { category: "knowledge-graphs", tags: %w[semantic knowledge graph embedding], arxiv_cat: "cs.AI", max: 8 }
].freeze

def fetch_arxiv_papers(cat, max_results)
  base_url = "https://export.arxiv.org/api/query"
  params = "search_query=cat:#{cat}&start=0&max_results=#{max_results}&sortBy=submittedDate&sortOrder=descending"
  uri = URI("#{base_url}?#{params}")
  response = Net::HTTP.get_response(uri)
  return [] unless response.is_a?(Net::HTTPSuccess)

  doc = REXML::Document.new(response.body)
  papers = []
  REXML::XPath.each(doc, "//entry") do |entry|
    id = REXML::XPath.first(entry, "id/text()").to_s
    id = id.sub("http://arxiv.org/abs/", "").sub("https://arxiv.org/abs/", "")
    title = REXML::XPath.first(entry, "title/text()").to_s.strip.gsub(/\s+/, " ")
    summary = REXML::XPath.first(entry, "summary/text()").to_s.strip.gsub(/\s+/, " ")
    published = REXML::XPath.first(entry, "published/text()").to_s[0..9]
    pdf_url = "#{SOURCE_URL}/pdf/#{id}"

    papers << {
      id: id,
      title: title,
      summary: summary,
      published: published,
      pdf_url: pdf_url,
      abs_url: "#{SOURCE_URL}/abs/#{id}"
    }
  end
  papers
end

def download_and_extract_text(pdf_url)
  # Download PDF, following redirects
  uri = URI(pdf_url)
  3.times do
    response = Net::HTTP.get_response(uri)
    case response
    when Net::HTTPRedirection
      uri = URI(response["location"])
      uri = URI("#{pdf_url.split("/")[0..2].join("/")}#{uri.path}") if uri.host.nil?
      next
    when Net::HTTPSuccess
      Tempfile.create(["arxiv", ".pdf"]) do |pdf_file|
        pdf_file.write(response.body)
        pdf_file.close

        # Extract text with pdftotext
        output, status = Open3.capture2("pdftotext", "-q", pdf_file.path, "-")
        return nil unless status.success?

        # Clean up text: remove excessive whitespace, page breaks
        text = output.gsub(/\f/, "\n\n").gsub(/\n{3,}/, "\n\n").strip

        # Truncate to ~3000 words for manageable test size
        words = text.split
        if words.length > 3500
          text = words.take(3500).join(" ") + "..."
        end

        return text
      end
    else
      return nil
    end
  end
  nil
end

def write_post(paper, category, tags, index)
  date = Date.new(2026, 2, 1) + index
  slug = paper[:id].tr(".", "-")
  filename = "#{date.strftime('%Y-%m-%d')}-arxiv-#{slug}.md"
  filepath = File.join(POSTS_DIR, filename)

  frontmatter = {
    "title" => paper[:title],
    "categories" => [category],
    "tags" => tags,
    "source" => SOURCE,
    "source_url" => paper[:abs_url],
    "arxiv_id" => paper[:id],
    "published" => paper[:published],
    "download_date" => DOWNLOAD_DATE,
    "license" => "arXiv non-exclusive license (see #{paper[:abs_url]})"
  }

  yaml = frontmatter.map do |k, v|
    if v.is_a?(Array)
      "#{k}:\n" + v.map { |item| "  - #{item}" }.join("\n")
    else
      "#{k}: #{v.to_s.inspect}"
    end
  end.join("\n")

  # Use abstract + extracted full text
  body = "## Abstract\n\n#{paper[:summary]}\n\n## Full text\n\n#{paper[:full_text]}"

  File.write(filepath, "---\n#{yaml}\n---\n\n#{body}\n")
  filepath
end

generated = []
skipped = []
index = 0

QUERIES.each do |query|
  puts "\nFetching papers from #{query[:arxiv_cat]} (#{query[:category]})..."
  papers = fetch_arxiv_papers(query[:arxiv_cat], query[:max])

  papers.each do |paper|
    print "  #{paper[:id]}: #{paper[:title][0..60]}... "
    full_text = download_and_extract_text(paper[:pdf_url])
    if full_text && full_text.split.length > 500
      paper[:full_text] = full_text
      path = write_post(paper, query[:category], query[:tags], index)
      words = File.read(path).split.length
      generated << { id: paper[:id], path: path, words: words }
      puts "#{words} words"
    else
      skipped << paper[:id]
      puts "FAILED (text too short or extraction failed)"
    end
    index += 1
    sleep 1 # Be polite to arXiv
  end
end

puts "\nGenerated #{generated.length} arXiv posts"
puts "Skipped: #{skipped.join(', ')}" unless skipped.empty?
total = generated.sum { |g| g[:words] }
puts "Total words: #{total}"
puts "Average: #{total / [generated.length, 1].max} words/post" if generated.any?
