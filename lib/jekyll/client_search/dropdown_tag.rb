# frozen_string_literal: true

require "cgi"

module Jekyll
  module ClientSearch
    # Liquid tag that renders a compact live-search dropdown suitable for
    # navbars and headers. Framework-agnostic — emits semantic HTML with
    # data attributes, no CSS classes from any framework.
    #
    #   {% search_dropdown %}
    #   {% search_dropdown max:10 %}
    #   {% search_dropdown scripts_only %}
    #   {% search_dropdown no_scripts %}
    #
    # When client_search is disabled the tag renders nothing.
    class DropdownTag < Liquid::Tag
      SYNTAX = /\A(max:(\d+))?\s*(scripts_only|no_scripts)?\z/

      def initialize(tag_name, markup, tokens)
        super
        @markup = markup.to_s.strip
        unless (match = @markup.match(SYNTAX))
          raise Liquid::SyntaxError,
                "search_dropdown: invalid syntax. Use {% search_dropdown %}, " \
                "{% search_dropdown max:10 %}, {% search_dropdown scripts_only %}, " \
                "or {% search_dropdown no_scripts %}"
        end

        @max_items = match[2].to_i if match[2]
        raise Liquid::SyntaxError, "search_dropdown: max must be greater than zero" if @max_items && @max_items < 1

        @mode = match[3] || "full"
        @input_id = "cs-dropdown-input-#{object_id}"
        @results_id = "cs-dropdown-results-#{object_id}"
      end

      def render(context)
        site = context.registers[:site]
        return "" unless enabled?(site)

        configuration = Configuration.new(site)
        return "" unless configuration.dropdown_enabled?

        render_mode(configuration, site)
      end

      private

      def enabled?(site)
        return false if site.nil?

        config_hash = site.config.fetch("client_search", {})
        config_hash != false && config_hash["enabled"] != false
      end

      def render_mode(configuration, site)
        baseurl = site.config["baseurl"].to_s.gsub(%r{\A/+|/+$}, "")
        prefix = baseurl.empty? ? "" : "/#{baseurl}"
        max = resolve_max(configuration)

        form_html = build_form(max)
        return form_html if @mode == "no_scripts"

        scripts = build_scripts(configuration, prefix)
        return scripts if @mode == "scripts_only"

        "#{form_html}\n#{scripts}"
      end

      def resolve_max(configuration)
        @max_items || configuration.dropdown_max_items
      end

      def build_form(max)
        <<~HTML
          <div class="client-search-dropdown" data-client-search-dropdown>
            <form role="search" autocomplete="off" data-cs-dropdown-form>
              <label class="sr-only" for="#{@input_id}">Search</label>
              <input id="#{@input_id}" type="search" name="q"
                     placeholder="Search…" autocomplete="off"
                     aria-expanded="false" aria-controls="#{@results_id}"
                     data-cs-dropdown-input>
            </form>
            <ul id="#{@results_id}" role="listbox" aria-hidden="true"
                data-cs-dropdown-results data-max-items="#{max}"></ul>
          </div>
        HTML
      end

      def build_scripts(configuration, prefix)
        scripts = []
        engine = configuration.engine_url
        if engine
          attrs = ["src=\"#{CGI.escapeHTML(engine)}\""]
          if configuration.engine_crossorigin
            crossorigin = CGI.escapeHTML(configuration.engine_crossorigin)
            attrs << "crossorigin=\"#{crossorigin}\""
          end
          if configuration.engine_sri
            integrity = CGI.escapeHTML(configuration.engine_sri)
            attrs << "integrity=\"#{integrity}\""
          end
          scripts << "<script #{attrs.join(' ')}></script>"
        end
        scripts << "<script src=\"#{prefix}/assets/search-runtime-config.js\"></script>"
        scripts << "<script src=\"#{prefix}/assets/client-search-dropdown.js\"></script>"
        scripts << "<script src=\"#{prefix}/assets/adapters/#{configuration.engine}.js\"></script>"
        scripts.map { |script| "  #{script}" }.join("\n")
      end
    end
  end
end

Liquid::Template.register_tag("search_dropdown", Jekyll::ClientSearch::DropdownTag)
