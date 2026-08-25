# frozen_string_literal: true

require "fileutils"
require "rubygems"

module Jekyll
  module ClientSearch
    # Rake tasks for inspecting and installing reference files.
    #
    # Tasks:
    #   jekyll_client_search:reference_files — list gem reference files,
    #     diff against site copies, offer to update
    #   jekyll_client_search:install — copy reference files into the site's
    #     _layouts/ and _includes/ directories
    module Tasks
      REFERENCE_FILES = {
        "assets/layouts/post-with-related.html" => "_layouts/post-with-related.html",
        "assets/includes/related-articles.html" => "_includes/related-articles.html"
      }.freeze

      class << self
        def gem_root
          spec = Gem::Specification.find_by_name("jekyll-client-search")
          spec.gem_dir
        rescue Gem::MissingSpecError
          # Fall back to the development source directory
          File.expand_path("../../..", __dir__)
        end

        def reference_files
          REFERENCE_FILES
        end

        def site_root
          Dir.pwd
        end

        def list_reference_files
          puts "jekyll-client-search reference files:"
          puts
          reference_files.each do |gem_rel, site_rel|
            gem_path = File.join(gem_root, gem_rel)
            site_path = File.join(site_root, site_rel)
            site_exists = File.exist?(site_path)

            status = if !site_exists
                       "not installed"
                     elsif same_content?(gem_path, site_path)
                       "up to date"
                     else
                       "modified or outdated"
                     end

            puts "  #{site_rel}"
            puts "    gem:     #{gem_path}"
            puts "    site:    #{site_path}"
            puts "    status:  #{status}"
            puts
          end
        end

        def diff_reference_files
          reference_files.each do |gem_rel, site_rel|
            gem_path = File.join(gem_root, gem_rel)
            site_path = File.join(site_root, site_rel)

            unless File.exist?(site_path)
              puts "#{site_rel}: not installed (no diff)"
              next
            end

            if same_content?(gem_path, site_path)
              puts "#{site_rel}: up to date"
            else
              puts "Diff for #{site_rel}:"
              system("diff", "-u", site_path, gem_path)
              puts
            end
          end
        end

        def install_reference_files(overwrite: false)
          installed = []
          skipped = []

          reference_files.each do |gem_rel, site_rel|
            result = install_file(gem_rel, site_rel, overwrite: overwrite)
            case result
            when :installed then installed << site_rel
            when :skipped then skipped << site_rel
            end
          end

          { installed: installed, skipped: skipped }
        end

        def install_file(gem_rel, site_rel, overwrite:)
          gem_path = File.join(gem_root, gem_rel)
          site_path = File.join(site_root, site_rel)

          unless File.exist?(gem_path)
            warn "  WARNING: gem file missing: #{gem_path}"
            return nil
          end

          return handle_existing(site_rel, gem_path, site_path) if File.exist?(site_path) && !overwrite

          copy_file(gem_path, site_path, site_rel, overwrite)
        end

        def handle_existing(site_rel, gem_path, site_path)
          if same_content?(gem_path, site_path)
            puts "  #{site_rel}: already up to date (skip)"
            nil
          else
            puts "  #{site_rel}: exists and differs (skip — use overwrite: true to replace)"
            :skipped
          end
        end

        def copy_file(gem_path, site_path, site_rel, overwrite)
          FileUtils.mkdir_p(File.dirname(site_path))
          FileUtils.cp(gem_path, site_path)
          action = overwrite ? "updated" : "installed"
          puts "  #{site_rel}: #{action}"
          :installed
        end

        def same_content?(path_a, path_b)
          File.read(path_a) == File.read(path_b)
        rescue Errno::ENOENT
          false
        end
      end
    end
  end
end
