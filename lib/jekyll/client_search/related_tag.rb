# frozen_string_literal: true

module Jekyll
  module ClientSearch
    # Liquid tag that renders the related-articles container, sort control,
    # and runtime scripts in one line. Drop into any post layout:
    #
    #   {% related_articles %}
    #   {% related_articles sort:date %}
    #   {% related_articles max:3 %}
    #   {% related_articles sort:date max:3 %}
    #   {% related_articles no_scripts %}
    #
    # When +related.enabled+ is false the tag renders nothing, so it is safe
    # to leave in a layout even when the feature is off.
    class RelatedTag < Liquid::Tag
      SYNTAX = /\A(sort:(\w+))?\s*(max:(\d+))?\s*(no_scripts)?\z/

      def initialize(tag_name, markup, tokens)
        super
        @markup = markup.to_s.strip
        unless (match = @markup.match(SYNTAX))
          raise Liquid::SyntaxError,
                "related_articles: invalid syntax. Use {% related_articles %}, " \
                "{% related_articles sort:date %}, {% related_articles max:3 %}, " \
                "or {% related_articles no_scripts %}"
        end

        @sort = match[2] if match[2]
        @max_items = match[4].to_i if match[4]
        raise Liquid::SyntaxError, "related_articles: max must be greater than zero" if @max_items && @max_items < 1

        @include_scripts = match[5].nil?
      end

      def render(context)
        site = context.registers[:site]
        return "" if site.nil?

        config = site.config.fetch("client_search", {})
        return "" if config == false
        return "" unless related_enabled?(config)

        asset_prefix = asset_prefix(site)
        sort_attr = @sort ? " data-related-sort=\"#{@sort}\"" : ""
        max_attr = resolve_max_attr(config)
        scripts = build_scripts(asset_prefix)
        build_html(sort_attr, max_attr, scripts)
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

      def resolve_max_attr(config)
        related = config.fetch("related", {})
        max = if @max_items
                @max_items
              elsif related.key?("max_items")
                related["max_items"]
              else
                5
              end
        max.nil? ? "" : " data-related-max=\"#{max}\""
      end

      def build_html(sort_attr, max_attr, scripts)
        <<~HTML
          <section class="related-articles-section">
            <label for="related-sort">Sort related articles</label>
            <select id="related-sort">
              <option value="relevance">Most related</option>
              <option value="date">Newest</option>
            </select>
            <div id="related-articles"#{sort_attr}#{max_attr}></div>
          </section>#{scripts}
        HTML
      end
    end
  end
end

Liquid::Template.register_tag("related_articles", Jekyll::ClientSearch::RelatedTag)
