module Tango
  module Compiler
    module Editor
      class Index
        # Classifies only identifiers whose identity or callable kind came from
        # the successful semantic snapshot. Keywords, punctuation, literals,
        # and other lexical surface remain the TextMate grammar's responsibility.
        private def build_semantic_tokens(facts : Analysis::Facts::Table) : Nil
          mutable_writes = facts.local_writes.keys.to_set
          @nodes.each_value do |node|
            mutable_writes << node.target.id if node.is_a?(IR::NIR::Assign)
          end

          declarations.each do |declaration|
            next if declaration.name == "self"
            next unless semantic_identifier?(declaration.name)
            range = identifier_range(declaration.range, declaration.name, declaration.kind)
            next unless range
            add_semantic_token(
              range,
              semantic_token_kind(declaration.kind),
              declaration: true,
              modification: mutable_writes.includes?(declaration.id.declaration)
            )
          end

          references.each do |reference|
            symbol = reference.declaration
            next unless symbol
            target = declaration(symbol)
            next unless target && semantic_identifier?(target.name)
            range = identifier_range(reference.range, target.name, symbol.kind)
            next unless range
            add_semantic_token(
              range,
              semantic_token_kind(symbol.kind),
              modification: mutable_writes.includes?(reference.node)
            )
          end

          semantic_nodes.each do |semantic|
            site = semantic.method_site
            range = site.try(&.name_span)
            next unless site && range && semantic_identifier?(site.name)
            range = callable_range(range, site.name)
            next unless range
            kind = site.kind.function? || site.kind.proc? ? SemanticTokenKind::Function : SemanticTokenKind::Method
            add_semantic_token(range, kind)
          end

          # Receiverless calls do not need punctuation to prove they are calls:
          # Crystal has already attached their selected targets to the NIR Call.
          # External top-level calls such as `puts line` have no Tango source
          # declaration, so retain that resolved call shape directly as a fact.
          @nodes.each_value do |node|
            next unless node.is_a?(IR::NIR::Call) && (range = node.name_span)
            next if node.targets.empty? || !semantic_identifier?(node.name)
            next if references.any? { |reference| reference.node == node.id && reference.range == range && reference.declaration }
            range = callable_range(range, node.name)
            next unless range
            kind = node.targets.all? { |target| target.owner.nil? || target.owner == "Program" } ? SemanticTokenKind::Function : SemanticTokenKind::Method
            add_semantic_token(range, kind)
          end

          @semantic_tokens.sort_by! do |token|
            {token.range.path, token.range.start_offset, token.range.end_offset, token.kind.to_s}
          end
        end

        private def semantic_token_kind(kind : SymbolKind) : SemanticTokenKind
          case kind
          in .class?, .struct?, .enum?, .type_alias?    then SemanticTokenKind::Class
          in .function?                                 then SemanticTokenKind::Function
          in .method?, .constructor?, .block_parameter? then SemanticTokenKind::Method
          in .local?                                    then SemanticTokenKind::Variable
          in .parameter?, .block_argument?              then SemanticTokenKind::Parameter
          in .field?, .enum_member?, .constant?         then SemanticTokenKind::Property
          end
        end

        private def semantic_identifier?(name : String) : Bool
          !!name.match(/\A[[:alpha:]_][[:alnum:]_]*[?!=]?\z/)
        end

        private def identifier_range(range : Source::Range, name : String, kind : SymbolKind) : Source::Range?
          bare = name.ends_with?('=') ? name.rchop('=') : name
          return range if range.length == bare.bytesize
          return unless kind.field? && range.length == bare.bytesize + 1

          Source::Range.new(
            range.path,
            range.start_offset + 1,
            range.end_offset,
            range.line,
            range.column.try { |column| column + 1 }
          )
        end

        private def callable_range(range : Source::Range, name : String) : Source::Range?
          bare = name.ends_with?('=') ? name.rchop('=') : name
          range if range.length == bare.bytesize
        end

        private def add_semantic_token(
          range : Source::Range,
          kind : SemanticTokenKind,
          declaration : Bool = false,
          modification : Bool = false,
        ) : Nil
          if index = @semantic_tokens.index { |token| token.range == range && token.kind == kind }
            current = @semantic_tokens[index]
            @semantic_tokens[index] = SemanticToken.new(
              range,
              kind,
              current.declaration || declaration,
              current.modification || modification
            )
          else
            @semantic_tokens << SemanticToken.new(range, kind, declaration, modification)
          end
        end
      end

      # Exact, protocol-neutral range query over immutable semantic token facts.
      module SemanticTokens
        enum Completeness
          Exact
        end

        record Result,
          tokens : Array(Index::SemanticToken),
          completeness : Completeness = Completeness::Exact

        def self.in(snapshot : Snapshot, path : String, start_offset : Int32, end_offset : Int32) : Result
          tokens = snapshot.editor_index.semantic_tokens.select do |token|
            range = token.range
            range.path == path && range.start_offset < end_offset && range.end_offset > start_offset
          end
          Result.new(tokens)
        end
      end
    end
  end
end
