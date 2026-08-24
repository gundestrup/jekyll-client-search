# frozen_string_literal: true

# Shared mock embedding adapter for tests that need to simulate
# LLM embedding generation without a running Ollama server.
class MockEmbeddingAdapter
  attr_reader :embedded_texts

  def initialize
    @embedded_texts = []
  end

  def embed(text)
    @embedded_texts << text
    # Generate a deterministic 768-dim vector from the text content
    # so different texts get different embeddings
    Array.new(768) { |i| ((text.hash.abs % 1000) + i).to_f / 1000.0 }
  end
end
