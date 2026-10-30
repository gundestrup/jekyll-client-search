# frozen_string_literal: true

require "yaml"
require "json"

# Shared helpers for specs that build sites via jekyll-test-harness.
module ClientSearchSiteHelpers
  # Renders a post source string (YAML front matter + body) for use as a
  # plain-string leaf inside a `jekyll_files` tree or a raw files hash.
  def post_source(frontmatter, content)
    "#{YAML.dump(frontmatter)}---\n#{content}\n"
  end

  # Builds the `_posts` branch of a files hash from post descriptors.
  # Each post is `{ filename:, title:, frontmatter: {}, content: }`.
  def post_files(*posts)
    entries = posts.each_with_object({}) do |post, tree|
      frontmatter = { "title" => post[:title] }.merge(post.fetch(:frontmatter, {}))
      tree[post[:filename]] = post_source(frontmatter, post.fetch(:content, "Content."))
    end
    { "_posts" => entries }
  end

  # Reads the generated search index from a built site's page list.
  def generated_documents(site, output = "/search-index.json")
    page = site.pages.find { |candidate| candidate.url == output }
    JSON.parse(page.content)
  end

  # Normalised relative paths of the runtime assets the generator registered.
  def runtime_asset_paths(site)
    site.static_files.map { |file| file.relative_path.to_s.delete_prefix("/") }
  end
end
