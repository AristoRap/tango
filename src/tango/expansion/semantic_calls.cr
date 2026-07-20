module Tango
  module Expansion
    # Converts only explicitly annotated, already-resolved ordinary calls into
    # target-neutral semantic collection operations. The original Call remains
    # attached as the fallback; no method-name matching or type inference occurs
    # here.
    module SemanticCalls
      def self.expand(call : IR::NIR::Call) : IR::NIR::Expr
        case semantic_kind(call)
        when "map"
          valid_transform?(call) ? IR::NIR::CollectionMap.new(call) : call
        when "filter_keep"
          valid_transform?(call) ? IR::NIR::CollectionFilter.new(call, IR::NIR::CollectionFilter::Mode::Keep) : call
        when "filter_reject"
          valid_transform?(call) ? IR::NIR::CollectionFilter.new(call, IR::NIR::CollectionFilter::Mode::Reject) : call
        when "each"
          valid_transform?(call) ? IR::NIR::CollectionEach.new(call) : call
        when "fold"
          valid_fold?(call) ? IR::NIR::CollectionFold.new(call) : call
        when "indexed_read"
          valid_indexed_read?(call) ? IR::NIR::IndexedRead.new(call) : call
        when "indexed_write"
          valid_indexed_write?(call) ? IR::NIR::IndexedWrite.new(call) : call
        else
          call
        end
      end

      private def self.semantic_kind(call : IR::NIR::Call) : String?
        call.targets.each do |target|
          target.annotations.each do |entry|
            next unless entry.path == ["TangoSemantic"]
            return entry.symbol_args.first?
          end
        end
        nil
      end

      private def self.valid_transform?(call : IR::NIR::Call) : Bool
        call.args.size == 1 && !call.block.nil?
      end

      private def self.valid_fold?(call : IR::NIR::Call) : Bool
        call.args.size == 2 && !call.block.nil?
      end

      private def self.valid_indexed_read?(call : IR::NIR::Call) : Bool
        call.args.size == 2 && call.block.nil?
      end

      private def self.valid_indexed_write?(call : IR::NIR::Call) : Bool
        call.args.size == 3 && call.block.nil?
      end
    end
  end
end
