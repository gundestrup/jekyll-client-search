# frozen_string_literal: true

require "spec_helper"
require "fileutils"
require "tmpdir"

RSpec.describe Jekyll::ElasticlunrSearch::Generator do
  def build_site(source, config = {})
    jekyll_config = Jekyll.configuration(
      { "source" => source, "destination" => File.join(source, "_site"), "quiet" => true }.merge(config)
    )
    site = Jekyll::Site.new(jekyll_config)
    site.read
    site
  end

  it "generates a configured JSON index from posts" do
    Dir.mktmpdir("elasticlunr-site") do |source|
      FileUtils.mkdir_p(File.join(source, "_posts"))
      File.write(File.join(source, "_config.yml"), "title: Test site\n")
      File.write(
        File.join(source, "_posts", "2026-01-01-example.md"),
        <<~MARKDOWN
          ---
          title: Example article
          categories:
            - family
          tags:
            - example
          ---
          Searchable content appears here.
        MARKDOWN
      )

      site = build_site(source)
      described_class.new.generate(site)

      page = site.pages.find { |candidate| candidate.url == "/search-index.json" }
      expect(page).not_to be_nil
      expect(JSON.parse(page.content)).to include(
        hash_including(
          "title" => "Example article",
          "content" => include("Searchable content appears here."),
          "categories" => ["family"],
          "tags" => ["example"]
        )
      )
    end
  end

  it "indexes configured custom collections without duplicating posts" do
    Dir.mktmpdir("elasticlunr-collections") do |source|
      FileUtils.mkdir_p(File.join(source, "_posts"))
      FileUtils.mkdir_p(File.join(source, "_docs"))
      File.write(
        File.join(source, "_config.yml"),
        <<~YAML
          collections:
            docs:
              output: false
          elasticlunr_search:
            collections:
              - posts
              - docs
        YAML
      )
      File.write(File.join(source, "_posts", "2026-01-01-post.md"), "---\ntitle: Post\n---\nPost")
      File.write(File.join(source, "_docs", "guide.md"), "---\ntitle: Guide\n---\nGuide")

      site = build_site(source)
      described_class.new.generate(site)
      documents = JSON.parse(site.pages.find { |page| page.url == "/search-index.json" }.content)

      expect(documents.map { |document| document["title"] }).to contain_exactly("Post", "Guide")
    end
  end
end
