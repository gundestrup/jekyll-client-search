# frozen_string_literal: true

require "bundler/gem_tasks"
require "rake"

VERSION_FILE = File.expand_path("lib/jekyll/client_search/version.rb", __dir__)
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

    content = File.read(VERSION_FILE)
    updated = content.sub(/VERSION = "[^"]+"/, "VERSION = \"#{next_version}\"")
    File.write(VERSION_FILE, updated)
    puts "Bumped #{current} -> #{next_version}"
    puts "Update CHANGELOG.md before committing or releasing."
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
