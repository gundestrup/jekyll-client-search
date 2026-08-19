# frozen_string_literal: true

module Jekyll
  module ElasticlunrSearch
    class SearchIndexPage < Jekyll::PageWithoutAFile
      def initialize(site, output, documents)
        super(site, site.source, File.dirname(output), File.basename(output))
        self.data = {}
        self.content = JSON.generate(documents)
      end
    end
  end
end
