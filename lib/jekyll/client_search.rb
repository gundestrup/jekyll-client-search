# frozen_string_literal: true

require "cgi"
require "json"
require "jekyll"
require "pathname"
require_relative "client_search/version"
require_relative "client_search/configuration"
require_relative "client_search/document_builder"
require_relative "client_search/search_index_page"
require_relative "client_search/index_cache"
require_relative "client_search/ollama_embedding_adapter"
require_relative "client_search/generator"
