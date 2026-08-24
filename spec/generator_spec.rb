# frozen_string_literal: true

require "spec_helper"
require "fileutils"
require "tmpdir"

RSpec.describe Jekyll::ClientSearch::Generator do
  def build_site(source, config = {})
    jekyll_config = Jekyll.configuration(
      { "source" => source, "destination" => File.join(source, "_site"), "quiet" => true }.merge(config)
    )
    site = Jekyll::Site.new(jekyll_config)
    site.read
    site
  end

  def write_post(source, name: "example", title: "Example article")
    FileUtils.mkdir_p(File.join(source, "_posts"))
    File.write(
      File.join(source, "_posts", "2026-01-01-#{name}.md"),
      <<~MARKDOWN
        ---
        title: #{title}
        categories:
          - family
        tags:
          - example
        ---
        Searchable content appears here.
      MARKDOWN
    )
  end

  def generated_documents(site, output = "/search-index.json")
    page = site.pages.find { |candidate| candidate.url == output }
    JSON.parse(page.content)
  end

  it "generates a JSON index and registers the packaged runtime asset" do
    Dir.mktmpdir("client-search-site") do |source|
      write_post(source)
      site = build_site(source)

      described_class.new.generate(site)

      expect(generated_documents(site)).to include(
        hash_including(
          "title" => "Example article",
          "content" => include("Searchable content appears here."),
          "categories" => ["family"],
          "tags" => ["example"]
        )
      )
      runtime_files = site.static_files.select do |file|
        file.relative_path.to_s.delete_prefix("/").start_with?("assets/")
      end
      expect(runtime_files.map { |file| file.relative_path.to_s.delete_prefix("/") })
        .to contain_exactly("assets/client-search-base.js", "assets/adapters/minisearch.js")
    end
  end

  it "indexes configured custom collections without duplicates" do
    Dir.mktmpdir("client-search-collections") do |source|
      write_post(source, name: "post", title: "Post")
      FileUtils.mkdir_p(File.join(source, "_docs"))
      File.write(File.join(source, "_docs", "guide.md"), "---\ntitle: Guide\n---\nGuide")
      site = build_site(
        source,
        "collections" => { "docs" => { "output" => false } },
        "client_search" => { "collections" => %w[posts docs posts] }
      )

      described_class.new.generate(site)

      expect(generated_documents(site).map { |document| document["title"] })
        .to contain_exactly("Post", "Guide")
    end
  end

  it "includes titled pages when configured" do
    Dir.mktmpdir("client-search-pages") do |source|
      File.write(File.join(source, "about.md"), "---\ntitle: About\n---\nAbout this site")
      site = build_site(source, "client_search" => { "include_pages" => true })

      described_class.new.generate(site)

      expect(generated_documents(site)).to include(
        hash_including("title" => "About", "content" => "About this site")
      )
    end
  end

  it "supports a nested output path and disabling the runtime asset" do
    Dir.mktmpdir("client-search-output") do |source|
      write_post(source)
      site = build_site(
        source,
        "client_search" => {
          "output" => "indexes/search.json",
          "copy_runtime" => false
        }
      )

      described_class.new.generate(site)

      expect(site.pages.map(&:url)).to include("/indexes/search.json")
      paths = site.static_files.map { |file| file.relative_path.to_s.delete_prefix("/") }
      expect(paths).not_to include("assets/client-search-base.js")
      expect(paths).not_to include("assets/adapters/minisearch.js")
    end
  end

  it "copies the base and adapter runtimes for the configured JS engine" do
    Dir.mktmpdir("client-search-elasticlunr") do |source|
      write_post(source)
      site = build_site(source, "client_search" => { "engine" => "elasticlunr" })

      described_class.new.generate(site)

      expect(site.pages.map(&:url)).to include("/search-index.json")
      expect(site.static_files.map { |file| file.relative_path.to_s.delete_prefix("/") })
        .to contain_exactly("assets/client-search-base.js", "assets/adapters/elasticlunr.js")
    end
  end

  it "copies the base and minisearch adapter runtimes by default" do
    Dir.mktmpdir("client-search-minisearch") do |source|
      write_post(source)
      site = build_site(source)

      described_class.new.generate(site)

      expect(site.static_files.map { |file| file.relative_path.to_s.delete_prefix("/") })
        .to contain_exactly("assets/client-search-base.js", "assets/adapters/minisearch.js")
    end
  end

  it "does nothing when disabled" do
    Dir.mktmpdir("client-search-disabled") do |source|
      write_post(source)
      site = build_site(source, "client_search" => false)

      expect { described_class.new.generate(site) }
        .not_to(change { [site.pages.size, site.static_files.size] })
    end
  end
end
