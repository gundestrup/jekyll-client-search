# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "fileutils"
require_relative "../lib/jekyll/client_search/tasks"

RSpec.describe Jekyll::ClientSearch::Tasks, :unit do
  let(:tmp_site) { Dir.mktmpdir("client-search-tasks") }

  after do
    FileUtils.rm_rf(tmp_site)
  end

  def with_site_root(root)
    original = Dir.pwd
    Dir.chdir(root)
    yield
  ensure
    Dir.chdir(original)
  end

  it "lists reference files with correct gem paths" do
    expect(described_class.reference_files).to include(
      "assets/layouts/post-with-related.html" => "_layouts/post-with-related.html",
      "assets/includes/related-articles.html" => "_includes/related-articles.html"
    )
  end

  it "reports not installed when site has no copies" do
    with_site_root(tmp_site) do
      expect { described_class.list_reference_files }.to output(/not installed/).to_stdout
    end
  end

  it "installs reference files into the site" do
    with_site_root(tmp_site) do
      result = described_class.install_reference_files
      expect(result[:installed]).to include(
        "_layouts/post-with-related.html",
        "_includes/related-articles.html"
      )
      expect(File.exist?(File.join(tmp_site, "_layouts/post-with-related.html"))).to be(true)
      expect(File.exist?(File.join(tmp_site, "_includes/related-articles.html"))).to be(true)
    end
  end

  it "reports up to date after install" do
    with_site_root(tmp_site) do
      described_class.install_reference_files
      expect { described_class.list_reference_files }.to output(/up to date/).to_stdout
    end
  end

  it "skips existing files that differ without overwrite" do
    with_site_root(tmp_site) do
      described_class.install_reference_files

      # Modify the installed copy
      layout_path = File.join(tmp_site, "_layouts/post-with-related.html")
      File.write(layout_path, "#{File.read(layout_path)}\n<!-- custom -->\n")

      result = described_class.install_reference_files
      expect(result[:skipped]).to include("_layouts/post-with-related.html")
      expect(result[:installed]).not_to include("_layouts/post-with-related.html")
    end
  end

  it "overwrites modified files when overwrite: true" do
    with_site_root(tmp_site) do
      described_class.install_reference_files

      layout_path = File.join(tmp_site, "_layouts/post-with-related.html")
      File.write(layout_path, "modified content")

      result = described_class.install_reference_files(overwrite: true)
      expect(result[:installed]).to include("_layouts/post-with-related.html")
      expect(File.read(layout_path)).to eq(File.read(File.join(described_class.gem_root,
                                                               "assets/layouts/post-with-related.html")))
    end
  end

  it "detects same content correctly" do
    with_site_root(tmp_site) do
      gem_path = File.join(described_class.gem_root, "assets/layouts/post-with-related.html")
      site_path = File.join(tmp_site, "_layouts/post-with-related.html")

      expect(described_class.same_content?(gem_path, site_path)).to be(false)

      FileUtils.mkdir_p(File.dirname(site_path))
      FileUtils.cp(gem_path, site_path)
      expect(described_class.same_content?(gem_path, site_path)).to be(true)
    end
  end

  it "diffs files that differ" do
    with_site_root(tmp_site) do
      described_class.install_reference_files

      layout_path = File.join(tmp_site, "_layouts/post-with-related.html")
      File.write(layout_path, "different content")

      expect { described_class.diff_reference_files }.to output(/Diff for/).to_stdout
    end
  end

  it "reports up to date in diff when files match" do
    with_site_root(tmp_site) do
      described_class.install_reference_files
      expect { described_class.diff_reference_files }.to output(/up to date/).to_stdout
    end
  end

  it "resolves gem root to a real directory" do
    expect(File.directory?(described_class.gem_root)).to be(true)
    expect(File.exist?(File.join(described_class.gem_root, "assets/layouts/post-with-related.html"))).to be(true)
  end
end
