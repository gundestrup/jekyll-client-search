# frozen_string_literal: true

module Jekyll
  module ClientSearch
    # Generates browser runtime settings shared by all search adapters.
    class RuntimeConfigPage < Jekyll::PageWithoutAFile
      def initialize(site, configuration)
        super(site, site.source, "assets", "search-runtime-config.js")
        self.data = { "layout" => nil, "sitemap" => false }
        defaults = {
          "indexUrl" => index_url(site, configuration.output),
          "liveSearch" => configuration.live_search_config
        }
        defaults["relatedUrl"] = index_url(site, configuration.related_output) if configuration.related_enabled?
        defaults["iconField"] = configuration.runtime_icon_field if configuration.runtime_icon_field
        defaults["dropdown"] = configuration.dropdown_config if configuration.dropdown_enabled?
        json = JSON.generate(defaults)
        self.content = "window.clientSearchConfig = (function (generated, existing) {" \
                       "var liveSearch = Object.assign({}, generated.liveSearch, existing.liveSearch || {});" \
                       "var dropdown = Object.assign({}, generated.dropdown, existing.dropdown || {});" \
                       "return Object.assign(generated, existing, " \
                       "{ liveSearch: liveSearch, dropdown: dropdown });" \
                       "}(#{json}, window.clientSearchConfig || {}));\n"
      end

      private

      def index_url(site, output)
        parts = [site.baseurl, output].map { |part| part.to_s.gsub(%r{\A/+|/+$}, "") }.reject(&:empty?)
        "/#{parts.join('/')}"
      end
    end
  end
end
