require "uri"

module Tango
  module Lsp
    # Converts between LSP document URIs and local compiler paths.
    module UriPath
      private def uri_to_path(uri : String) : String
        path = URI.parse(uri).path
        path.empty? ? uri : URI.decode(path)
      rescue
        uri
      end

      private def path_to_uri(path : String) : String
        "file://#{URI.encode_path(path)}"
      end
    end
  end
end
