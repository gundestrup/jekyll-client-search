# frozen_string_literal: true

require "spec_helper"

RSpec.describe Jekyll::ClientSearch::DropdownConfiguration, :unit do
  def dropdown(config = {})
    described_class.new(config)
  end

  it "uses safe defaults" do
    settings = dropdown

    expect(settings).to be_enabled
    expect(settings.max_items).to eq(5)
    expect(settings.min_chars).to eq(2)
    expect(settings.debounce_ms).to eq(150)
    expect(settings.redirect_url).to eq("/search/")
  end

  it "returns false for enabled? when enabled is false" do
    expect(dropdown("enabled" => false)).not_to be_enabled
  end

  it "returns a hash with camelCase keys from to_h" do
    expect(dropdown.to_h).to eq(
      "enabled" => true,
      "maxItems" => 5,
      "minChars" => 2,
      "debounceMs" => 150,
      "redirectUrl" => "/search/"
    )
  end

  it "round-trips overridden values through to_h" do
    settings = dropdown(
      "enabled" => false,
      "max_items" => 10,
      "min_chars" => 0,
      "debounce_ms" => 0,
      "redirect_url" => "/search-articles/"
    )
    expect(settings.to_h).to eq(
      "enabled" => false,
      "maxItems" => 10,
      "minChars" => 0,
      "debounceMs" => 0,
      "redirectUrl" => "/search-articles/"
    )
  end

  it "raises when config is not a Hash" do
    expect { described_class.new("not a hash") }
      .to raise_error(Jekyll::Errors::FatalException, /must be a mapping/)
  end

  it "raises when enabled is not a boolean" do
    expect { dropdown("enabled" => "yes") }
      .to raise_error(Jekyll::Errors::FatalException, /enabled must be true or false/)
  end

  it "raises when max_items is not a positive integer" do
    expect { dropdown("max_items" => 0) }
      .to raise_error(Jekyll::Errors::FatalException, /max_items must be an integer/)
    expect { dropdown("max_items" => -1) }
      .to raise_error(Jekyll::Errors::FatalException, /max_items must be an integer/)
    expect { dropdown("max_items" => "5") }
      .to raise_error(Jekyll::Errors::FatalException, /max_items must be an integer/)
  end

  it "raises when min_chars is not a non-negative integer" do
    expect { dropdown("min_chars" => -1) }
      .to raise_error(Jekyll::Errors::FatalException, /min_chars must be an integer/)
    expect { dropdown("min_chars" => "2") }
      .to raise_error(Jekyll::Errors::FatalException, /min_chars must be an integer/)
  end

  it "raises when debounce_ms is not a non-negative integer" do
    expect { dropdown("debounce_ms" => -1) }
      .to raise_error(Jekyll::Errors::FatalException, /debounce_ms must be an integer/)
  end

  it "raises when redirect_url is an empty string" do
    expect { dropdown("redirect_url" => "") }
      .to raise_error(Jekyll::Errors::FatalException, /redirect_url must not be empty/)
  end
end
