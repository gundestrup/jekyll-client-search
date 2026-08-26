# frozen_string_literal: true

require "bundler/gem_tasks"
require "rake"
require_relative "lib/jekyll/client_search/tasks"

VERSION_FILE = File.expand_path("lib/jekyll/client_search/version.rb", __dir__)
PACKAGE_FILE = File.expand_path("package.json", __dir__)
GEMSPEC_FILE = File.expand_path("jekyll-client-search.gemspec", __dir__)

namespace :version do
  desc "Print the current gem version"
  task :show do
    puts File.read(VERSION_FILE)[/VERSION = "([^"]+)"/, 1]
  end

  desc "Bump the gem version: bundle exec rake 'version:bump[patch]'"
  task :bump, [:part] do |_task, args|
    part = args[:part].to_s
    abort "Usage: bundle exec rake 'version:bump[major|minor|patch]'" unless %w[major minor patch].include?(part)

    current = Gem::Version.new(File.read(VERSION_FILE)[/VERSION = "([^"]+)"/, 1])
    segments = current.segments
    index = { "major" => 0, "minor" => 1, "patch" => 2 }.fetch(part)
    segments[index] += 1
    ((index + 1)...segments.length).each { |position| segments[position] = 0 }
    next_version = segments.join(".")

    # Update version.rb (source of truth — gemspec reads from here)
    content = File.read(VERSION_FILE)
    updated = content.sub(/VERSION = "[^"]+"/, "VERSION = \"#{next_version}\"")
    File.write(VERSION_FILE, updated)

    # Update package.json (kept in sync — not used by runtime, but avoids drift)
    pkg = File.read(PACKAGE_FILE)
    pkg_updated = pkg.sub(/"version": "[^"]+"/, "\"version\": \"#{next_version}\"")
    File.write(PACKAGE_FILE, pkg_updated)

    puts "Bumped #{current} -> #{next_version}"
    puts "Updated: #{VERSION_FILE}, #{PACKAGE_FILE}"
    puts "Update CHANGELOG.md before committing or releasing."
  end
end

namespace :jekyll_client_search do
  desc "List reference files, show diff against site copies, and offer to update"
  task :reference_files do
    Jekyll::ClientSearch::Tasks.list_reference_files
    puts "Diff against installed copies:"
    puts
    Jekyll::ClientSearch::Tasks.diff_reference_files
    puts "To install or update, run: bundle exec rake jekyll_client_search:install"
  end

  desc "Copy reference layouts and includes into the site (use overwrite=true to replace modified copies)"
  task :install, [:overwrite] do |_task, args|
    overwrite = args[:overwrite] == "true"
    puts "Installing jekyll-client-search reference files into #{Jekyll::ClientSearch::Tasks.site_root}:"
    result = Jekyll::ClientSearch::Tasks.install_reference_files(overwrite: overwrite)
    puts
    puts "Installed/updated: #{result[:installed].join(', ')}" if result[:installed].any?
    if result[:skipped].any?
      puts "Skipped (exists, differs): #{result[:skipped].join(', ')}"
      puts "Run with overwrite=true to replace: bundle exec rake 'jekyll_client_search:install[true]'"
    end
    puts
    puts "These files are starting points — customize them freely."
    puts "For upgrade-safe adoption without copying files, use the Liquid tags:"
    puts "  {% search_form %}        — search form + scripts (config-driven)"
    puts "  {% related_articles %}   — related articles section"
  end
end

desc "Run the test suite and Ruby syntax checks"
task :ci do
  sh "bundle exec rspec"
  sh "bundle exec rubocop"
  sh "bundle exec ruby -c lib/jekyll/client_search.rb"
  sh "bundle exec ruby -c lib/jekyll/client_search/generator.rb"
  sh "npm test"
  sh "gem build #{GEMSPEC_FILE}"
end

# Default task: run all quality checks (most common use case)
task default: :quality

desc "Run all quality checks (style, security, tests)"
task quality: %i[rubocop bundler_audit spec npm_test]

desc "Run quick checks (style + tests only)"
task quick: %i[rubocop spec] do
  puts "✅ Quick checks passed"
end

desc "Check code style with RuboCop"
task :rubocop do
  sh "bundle exec rubocop"
end

desc "Auto-fix RuboCop issues"
task :rubocop_fix do
  sh "bundle exec rubocop -a"
end

desc "Run security audit"
task :bundler_audit do
  sh "bundle exec bundler-audit check --update"
end

desc "Run JavaScript tests"
task :npm_test do
  sh "npm test"
end

desc "Run Ruby tests"
task :spec do
  sh "bundle exec rspec"
end
