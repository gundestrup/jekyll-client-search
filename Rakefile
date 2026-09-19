# frozen_string_literal: true

require "bundler/gem_tasks"
require "rake"
require_relative "lib/jekyll/client_search/tasks"

VERSION_FILE = File.expand_path("lib/jekyll/client_search/version.rb", __dir__)
CHANGELOG_FILE = File.expand_path("CHANGELOG.md", __dir__)
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
    puts "Updated: #{VERSION_FILE}"
    puts "Add a '## #{next_version} — YYYY-MM-DD' entry to CHANGELOG.md before committing."
  end

  desc "Verify CHANGELOG.md has an entry for the current version"
  task :check_changelog do
    version = File.read(VERSION_FILE)[/VERSION = "([^"]+)"/, 1]
    changelog = File.read(CHANGELOG_FILE)
    unless changelog.match?(/^## #{Regexp.escape(version)}\b/)
      abort "CHANGELOG.md has no '## #{version}' entry. Add one before releasing."
    end
    puts "✅ CHANGELOG.md has an entry for version #{version}"
  end

  desc "Verify version literals: docs match gemspec floor, pins match .ruby-version"
  task :check_consistency do
    # Two sources, two axes: the gemspec floor (consumer minimum, tested
    # by the CI matrix) and .ruby-version (dev/release pin). They differ
    # deliberately here — floor literals check against the gemspec,
    # full X.Y.Z pins check against .ruby-version.
    floor = File.read(GEMSPEC_FILE)[/required_ruby_version\s*=\s*">=\s*([\d.]+)"/, 1]
    pin = File.read(".ruby-version").strip
    # Normalize to major.minor — "3.2.0" floor and "3.2" literals are equal
    floor_minor = floor.to_s[/\d+\.\d+/]
    pin_minor = pin[/\d+\.\d+/]
    abort "Could not read gemspec floor or .ruby-version pin" unless floor_minor && pin

    problems = []

    # Static config that can't derive: .rubocop.yml TargetRubyVersion (floor axis)
    problems += File.read(".rubocop.yml").scan(/TargetRubyVersion:\s*([\d.]+)/).filter_map do |m|
      ".rubocop.yml: TargetRubyVersion #{m[0]} != gemspec floor #{floor_minor}" if m[0] != floor_minor
    end

    # CHANGELOG and generated reports are historical — old entries cite
    # old versions legitimately.
    `git ls-files '*.md' '*.json' '*.yml'`.split
                                          .grep_v(%r{CHANGELOG|test_logs/|README\.performance}).each do |file|
      content = File.read(file)

      # Floor literals: "Ruby >= X.Y", "Ruby X.Y+", badge "ruby-≥ X.Y"
      content.scan(/Ruby\s*(?:>=\s*|≥\s*|%E2%89%A5%20)(\d+\.\d+)/i).each do |m|
        problems << "#{file}: floor literal #{m[0]} != gemspec floor #{floor_minor}" if m[0] != floor_minor
      end

      # Bare "Ruby X.Y" is ambiguous — must match floor OR the pin's
      # minor (a doc describing either axis is fine; anything else drifts)
      content.scan(/Ruby\s+(\d+\.\d+)\b(?!\.)/i).each do |m|
        next if [floor_minor, pin_minor].include?(m[0])

        problems << "#{file}: 'Ruby #{m[0]}' matches neither floor #{floor_minor} nor pin #{pin_minor}"
      end

      # Full X.Y.Z pins on Ruby-ish lines must equal .ruby-version
      content.scan(/^.*(?:ruby|rbenv).*$/i).each do |line|
        line.scan(/\b(\d+\.\d+\.\d+)\b/).each do |m|
          problems << "#{file}: pin literal #{m[0]} != .ruby-version #{pin}" if m[0] != pin
        end
      end
    end

    if problems.empty?
      puts "✅ Version literals consistent (floor #{floor}, pin #{pin})"
    else
      problems.uniq.each { |problem| warn "❌ #{problem}" }
      abort "Update the literal or its source — don't let docs drift."
    end
  end

  desc "Pre-release gate: CHANGELOG entry + version consistency"
  task pre_release: %i[check_changelog check_consistency] do
    version = File.read(VERSION_FILE)[/VERSION = "([^"]+)"/, 1]
    puts ""
    puts "✅ Pre-release checks complete for version #{version}"
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
