# frozen_string_literal: true

require "simplecov"
require "simplecov-cobertura" if ENV["CI"]

SimpleCov.start do
  enable_coverage :branch
  skip "/spec/"
  cover "lib/**/*.rb"
  minimum_coverage line: 85, branch: 75 if ENV["CI"] || ENV["COVERAGE"]
  if ENV["CI"]
    formatter SimpleCov::Formatter::MultiFormatter.new(
      [SimpleCov::Formatter::CoberturaFormatter, SimpleCov::Formatter::JSONFormatter]
    )
  end
end

require "bundler/setup"
require "jekyll-client-search"
require "jekyll_test_harness"

Dir.glob(File.expand_path("support/**/*.rb", __dir__), sort: true).each { |f| require f }

# Install the Jekyll integration harness so specs can build real sites
# with `jekyll_build`/`jekyll_files` instead of hand-rolled tmpdir setup.
JekyllTestHarness.install!(framework: :rspec)

RSpec.configure do |config|
  config.example_status_persistence_file_path = ".rspec_status"
  config.include ClientSearchSiteHelpers
end
