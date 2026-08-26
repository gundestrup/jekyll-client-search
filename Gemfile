# frozen_string_literal: true

source "https://rubygems.org"

gemspec

group :development, :test do
  gem "benchmark", "~> 0.5"
  gem "bundler-audit", "~> 0.9"
  gem "ollama-ruby", "~> 1.23"
  gem "rake", "~> 13.2"
  gem "reek", "~> 6.5"
  gem "rspec", "~> 3.13"
end

gem "rubocop", "~> 1.90", group: :development

gem "rubocop-rspec", "~> 3.10", group: :development

gem "simplecov", "~> 1.1", group: :test

# rbs 4.2+, excon 1.7+, and parallel 2.1+ require Ruby >= 3.3.
# Pin to keep Ruby 3.2 support (gemspec requires >= 3.2.0).
gem "excon", "~> 1.6.0", group: :development
gem "parallel", "~> 1.28", group: :development
gem "rbs", "~> 4.1.0", group: :development
