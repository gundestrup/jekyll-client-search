# frozen_string_literal: true

require "cgi"

module Jekyll
  module ClientSearch
    # Shared <script> tag assembly for the client-search Liquid tags so each
    # tag only declares its own asset file.
    module ScriptTags
      private

      def script_tags(configuration, prefix, tag_asset, extra: [])
        scripts = []
        engine = engine_script(configuration)
        scripts << engine if engine
        scripts << "<script src=\"#{prefix}/assets/search-runtime-config.js\"></script>"
        scripts.concat(extra)
        scripts << "<script src=\"#{prefix}/assets/client-search-shared.js\"></script>"
        scripts << "<script src=\"#{prefix}/assets/#{tag_asset}\"></script>"
        scripts << "<script src=\"#{prefix}/assets/adapters/#{configuration.engine}.js\"></script>"
        scripts.map { |script| "  #{script}" }.join("\n")
      end

      def engine_script(configuration)
        url = configuration.engine_url
        return nil unless url

        attrs = ["src=\"#{CGI.escapeHTML(url)}\""]
        if configuration.engine_crossorigin
          crossorigin = CGI.escapeHTML(configuration.engine_crossorigin)
          attrs << "crossorigin=\"#{crossorigin}\""
        end
        if configuration.engine_sri
          integrity = CGI.escapeHTML(configuration.engine_sri)
          attrs << "integrity=\"#{integrity}\""
        end
        "<script #{attrs.join(' ')}></script>"
      end
    end
  end
end
