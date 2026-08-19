# frozen_string_literal: true

module Jekyll
  module ClientSearch
    class SearchIndexPage < Jekyll::PageWithoutAFile
      def initialize(site, output, documents)
        super(site, site.source, File.dirname(output), File.basename(output))
        self.data = { "layout" => nil, "sitemap" => false }
        self.content = JSON.generate(documents)
      end
    end
  end
end
