module Tango
  module IR
    module LIR
      # Planned Array, Hash, materialization, and collection-traversal values.
      class ArrayNew < Value
        getter type : IR::Type
        getter element : IR::Type

        def initialize(@type : IR::Type, @element : IR::Type)
        end
      end

      class ArrayBuild < Value
        getter type : IR::Type
        getter element : IR::Type
        getter size : Value

        def initialize(@type : IR::Type, @element : IR::Type, @size : Value)
        end
      end

      abstract class ArrayOperation < Value
        getter array : Value
        getter element : IR::Type

        def initialize(@array : Value, @element : IR::Type)
        end
      end

      class ArrayGet < ArrayOperation
        getter index : Value

        def initialize(array : Value, @index : Value, element : IR::Type)
          super(array, element)
        end
      end

      class ArraySet < ArrayOperation
        getter index : Value
        getter value : Value

        def initialize(array : Value, @index : Value, @value : Value, element : IR::Type)
          super(array, element)
        end
      end

      class ArrayPush < ArrayOperation
        getter value : Value

        def initialize(array : Value, @value : Value, element : IR::Type)
          super(array, element)
        end
      end

      class MaterializedStringSplit < Value
        getter string : Value
        getter type : IR::Type
        getter separator : Value?

        def initialize(@string : Value, @type : IR::Type, @separator : Value? = nil)
        end

        def element : IR::Type
          type.element_type || IR::Type.unknown
        end
      end

      abstract class HashValue < Value
        getter hash_type : IR::Type

        def initialize(@hash_type : IR::Type)
        end

        def key_type : IR::Type
          hash_type.key_type || IR::Type.unknown
        end

        def value_type : IR::Type
          hash_type.value_type || IR::Type.unknown
        end
      end

      class HashNew < HashValue
        def initialize(hash_type : IR::Type)
          super(hash_type)
        end
      end

      class HashGet < HashValue
        getter hash : Value
        getter key : Value

        def initialize(@hash : Value, @key : Value, hash_type : IR::Type)
          super(hash_type)
        end
      end

      class HashSet < HashValue
        getter hash : Value
        getter key : Value
        getter value : Value

        def initialize(@hash : Value, @key : Value, @value : Value, hash_type : IR::Type)
          super(hash_type)
        end
      end

      class HashFetch < HashValue
        getter hash : Value
        getter key : Value
        getter default : Value

        def initialize(@hash : Value, @key : Value, @default : Value, hash_type : IR::Type)
          super(hash_type)
        end
      end

      class HashHasKey < HashValue
        getter hash : Value
        getter key : Value

        def initialize(@hash : Value, @key : Value, hash_type : IR::Type)
          super(hash_type)
        end
      end

      class HashKeyAt < HashValue
        getter hash : Value
        getter index : Value

        def initialize(@hash : Value, @index : Value, hash_type : IR::Type)
          super(hash_type)
        end
      end

      abstract class CollectionSource
        getter value : Value

        def initialize(@value : Value)
        end
      end

      class ArrayElements < CollectionSource
        getter element : IR::Type

        def initialize(value : Value, @element : IR::Type)
          super(value)
        end
      end

      class HashEntries < CollectionSource
        getter hash_type : IR::Type

        def initialize(value : Value, @hash_type : IR::Type)
          super(value)
        end
      end

      class StringCodepoints < CollectionSource
      end

      class StringSegments < CollectionSource
        getter separator : Value

        def initialize(value : Value, @separator : Value)
          super(value)
        end
      end

      class CollectionCount < Value
        getter source : CollectionSource

        def initialize(@source : CollectionSource)
        end
      end

      abstract class CollectionTransform
        getter block : Closure

        def initialize(@block : Closure)
        end
      end

      class CollectionFilterTransform < CollectionTransform
      end

      class CollectionMapTransform < CollectionTransform
      end

      abstract class CollectionTerminal
        getter block : Closure

        def initialize(@block : Closure)
        end
      end

      class CollectionFoldTerminal < CollectionTerminal
        getter initial : Value
        getter type : IR::Type

        def initialize(@initial : Value, block : Closure, @type : IR::Type)
          super(block)
        end
      end

      class CollectionEachTerminal < CollectionTerminal
      end

      class FusedCollectionTraversal < Value
        getter source : CollectionSource
        getter transforms : Array(CollectionTransform)
        getter terminal : CollectionTerminal
        getter type : IR::Type

        def initialize(@source : CollectionSource, @transforms : Array(CollectionTransform), @terminal : CollectionTerminal, @type : IR::Type)
        end
      end
    end
  end
end
