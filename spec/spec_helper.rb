# frozen_string_literal: true

require "simplecov"
require "simplecov-cobertura" if ENV["CI"]

SimpleCov.start do
  enable_coverage :branch
  skip "/spec/"
  cover "lib/**/*.rb"
  minimum_coverage line: 85, branch: 75 if ENV["CI"] || ENV["COVERAGE"]
  formatter SimpleCov::Formatter::CoberturaFormatter if ENV["CI"]
end

require "bundler/setup"
require "jekyll-client-search"

RSpec.configure do |config|
  config.example_status_persistence_file_path = ".rspec_status"
end
