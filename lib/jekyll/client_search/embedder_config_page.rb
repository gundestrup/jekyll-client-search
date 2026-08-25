# frozen_string_literal: true

module Jekyll
  module ClientSearch
    # Generates the browser query-embedder configuration JavaScript.
    class EmbedderConfigPage < Jekyll::PageWithoutAFile
      def initialize(site, configuration)
        super(site, site.source, "assets", "search-embedder-config.js")
        self.data = { "layout" => nil, "sitemap" => false }
        self.content = "window.ClientSearchEmbedderConfig = #{configuration.query_embedder_config_json};\n"
      end
    end
  end
end
