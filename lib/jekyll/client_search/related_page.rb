# frozen_string_literal: true

module Jekyll
  module ClientSearch
    # Writes build-time related-article data as a standalone JSON page.
    class RelatedPage < Jekyll::PageWithoutAFile
      def initialize(site, output, relation_data)
        super(site, site.source, File.dirname(output), File.basename(output))
        self.data = { "layout" => nil, "sitemap" => false }
        self.content = JSON.generate(relation_data)
      end
    end
  end
end
