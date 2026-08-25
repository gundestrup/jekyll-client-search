# frozen_string_literal: true

module Jekyll
  module ClientSearch
    # Liquid tag that renders the related-articles container, sort control,
    # and runtime scripts in one line. Drop into any post layout:
    #
    #   {% related_articles %}
    #   {% related_articles sort:date %}
    #   {% related_articles no_scripts %}
    #
    # When +related.enabled+ is false the tag renders nothing, so it is safe
    # to leave in a layout even when the feature is off.
    class RelatedTag < Liquid::Tag
      SYNTAX = /\A\s*(sort:(\w+))?\s*(no_scripts)?\s*\z/

      def initialize(tag_name, markup, tokens)
        super
        @markup = markup.to_s
        unless (match = @markup.match(SYNTAX))
          raise Liquid::SyntaxError,
                "related_articles: invalid syntax. Use {% related_articles %}, " \
                "{% related_articles sort:date %}, or {% related_articles no_scripts %}"
        end

        @sort = match[2] if match[2]
        @include_scripts = match[3].nil?
      end

      def render(context)
        site = context.registers[:site]
        config = site&.config&.fetch("client_search", {})
        return "" unless related_enabled?(config)

        asset_prefix = asset_prefix(site)
        sort_attr = @sort ? " data-related-sort=\"#{@sort}\"" : ""
        scripts = build_scripts(asset_prefix)
        build_html(sort_attr, scripts)
      end

      private

      def related_enabled?(config)
        related = config.fetch("related", {})
        related["enabled"] == true
      end

      def asset_prefix(site)
        baseurl = site.config["baseurl"].to_s.gsub(%r{\A/+|/+$}, "")
        baseurl.empty? ? "" : "/#{baseurl}"
      end

      def build_scripts(prefix)
        return "" unless @include_scripts

        "\n<script src=\"#{prefix}/assets/search-runtime-config.js\"></script>\n" \
          "<script src=\"#{prefix}/assets/client-search-related.js\"></script>"
      end

      def build_html(sort_attr, scripts)
        <<~HTML
          <section class="related-articles-section">
            <label for="related-sort">Sort related articles</label>
            <select id="related-sort">
              <option value="relevance">Most related</option>
              <option value="date">Newest</option>
            </select>
            <div id="related-articles"#{sort_attr}></div>
          </section>#{scripts}
        HTML
      end
    end
  end
end

Liquid::Template.register_tag("related_articles", Jekyll::ClientSearch::RelatedTag)
