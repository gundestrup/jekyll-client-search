# frozen_string_literal: true

module Jekyll
  module ClientSearch
    # Liquid tag that renders the search form, status/results containers,
    # and all runtime scripts in one line — config-driven so changing engines
    # in _config.yml requires zero template changes.
    #
    #   {% search_form %}
    #   {% search_form scripts_only %}  — just scripts (custom form HTML)
    #   {% search_form no_scripts %}    — just form HTML (user loads scripts)
    #
    # When client_search is disabled the tag renders nothing.
    class SearchTag < Liquid::Tag
      SYNTAX = /\A(scripts_only|no_scripts)?\z/

      def initialize(tag_name, markup, tokens)
        super
        @markup = markup.to_s.strip
        unless (match = @markup.match(SYNTAX))
          raise Liquid::SyntaxError,
                "search_form: invalid syntax. Use {% search_form %}, " \
                "{% search_form scripts_only %}, or {% search_form no_scripts %}"
        end

        @mode = match[1] || "full"
      end

      def render(context)
        site = context.registers[:site]
        config_hash = site&.config&.fetch("client_search", {})
        return "" unless config_hash["enabled"] != false

        configuration = Configuration.new(site)
        baseurl = site.config["baseurl"].to_s.gsub(%r{\A/+|/+$}, "")
        prefix = baseurl.empty? ? "" : "/#{baseurl}"

        form_html = build_form
        return form_html if @mode == "no_scripts"

        scripts = build_scripts(configuration, prefix)
        return scripts if @mode == "scripts_only"

        "#{form_html}\n#{scripts}"
      end

      private

      def build_form
        <<~HTML
          <form id="search-form" role="search">
            <label class="is-sr-only" for="search-query">Search</label>
            <input id="search-query" type="search" name="q" placeholder="Search">
            <button type="submit">Search</button>
          </form>
          <div id="search-status" aria-live="polite"></div>
          <div id="search-results"></div>
        HTML
      end

      def build_scripts(configuration, prefix)
        scripts = []
        engine = engine_script(configuration)
        scripts << engine if engine
        scripts << "<script src=\"#{prefix}/assets/search-runtime-config.js\"></script>"
        scripts.concat(embedder_scripts(configuration, prefix))
        scripts << "<script src=\"#{prefix}/assets/client-search-base.js\"></script>"
        scripts << "<script src=\"#{prefix}/assets/adapters/#{configuration.engine}.js\"></script>"
        scripts.map { |script| "  #{script}" }.join("\n")
      end

      def engine_script(configuration)
        url = configuration.engine_url
        return nil unless url

        attrs = ["src=\"#{url}\""]
        attrs << "crossorigin=\"#{configuration.engine_crossorigin}\"" if configuration.engine_crossorigin
        attrs << "integrity=\"#{configuration.engine_sri}\"" if configuration.engine_sri
        "<script #{attrs.join(' ')}></script>"
      end

      def embedder_scripts(configuration, prefix)
        return [] unless semantic_with_embedder?(configuration)

        scripts = ["<script src=\"#{prefix}/assets/search-embedder-config.js\"></script>"]
        embedder_asset = configuration.query_embedder_asset
        scripts << "<script src=\"#{prefix}/#{embedder_asset}\"></script>" if embedder_asset
        scripts
      end

      def semantic_with_embedder?(configuration)
        configuration.engine == "semantic" &&
          configuration.embedding_enabled? &&
          configuration.query_embedder_type != "none"
      end
    end
  end
end

Liquid::Template.register_tag("search_form", Jekyll::ClientSearch::SearchTag)
