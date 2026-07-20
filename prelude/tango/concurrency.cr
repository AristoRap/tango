@[Primitive(:tango_go)]
def __tango_go(f : ->) : Nil
end

# A real forwarding def (not bodyless) so the block acquires its `->` type and
# `spawn` resolves as an internal def for tooling; `__tango_go` is the goroutine
# primitive it hands the block to.
def spawn(&block : ->) : Nil
  __tango_go(block)
end

@[GoType(:native_channel)]
class Channel(T)
  include Iterator(T)

  @[Primitive(:tango_chan_new)]
  def self.new : Channel(T)
  end

  @[Primitive(:tango_chan_new)]
  def self.new(capacity : Int32) : Channel(T)
  end

  @[Primitive(:tango_chan_send)]
  def send(value : T) : Nil
  end

  @[Primitive(:tango_chan_receive)]
  def receive : T
  end

  @[Primitive(:tango_chan_receive_q)]
  def receive? : T?
  end

  # The operational leaf returns data and closed state separately so `next`
  # never confuses a Nil element with closure. The public Iterator method is an
  # ordinary Tango body that maps only the closed state to Iterator::Stop.
  @[Primitive(:tango_chan_next_state)]
  @[TangoInternal]
  def __tango_next_state : ChannelNextState(T)
  end

  def next : T | Iterator::Stop
    state = self.__tango_next_state
    if state.open?
      state.value
    else
      Iterator::Stop.new(true)
    end
  end

  @[Primitive(:tango_chan_close)]
  def close : Nil
  end

  # `select` plumbing. Crystal's semantic phase rewrites a `select` keyword into
  # `%i, %v = Channel.select({ch.receive_select_action, ...})` + an if-chain; the
  # frontend recognizes the surface `select` and lowers it to a native Go
  # `select`. These defs only make that expansion type-check — none is ever
  # lowered or emitted.
  @[TangoInternal]
  def receive_select_action : SelectAction(T)
    SelectAction(T).new(self)
  end

  @[TangoInternal]
  def receive_select_action? : ReceiveMaybeSelectAction(T)
    ReceiveMaybeSelectAction(T).new(self)
  end

  @[TangoInternal]
  def send_select_action(value : T) : SelectAction(T)
    SelectAction(T).new(self)
  end

  @[TangoInternal]
  def self.select(actions : A) forall A
    {0, actions.tango_select_sample}
  end

  @[TangoInternal]
  def self.non_blocking_select(actions : A) forall A
    {0, actions.tango_select_sample}
  end
end

# Structured result of Channel's closed-aware receive leaf. It remains private
# plumbing: user code sees only `T | Iterator::Stop` from `Channel#next`.
struct ChannelNextState(T)
  @[TangoInternal]
  def initialize(@value : T, @open : Bool)
  end

  @[TangoInternal]
  def value : T
    @value
  end

  @[TangoInternal]
  def open? : Bool
    @open
  end
end

# The receive? select marker keeps the channel's element `T` while exposing a
# `T?` sample to Crystal's expansion. It is type-only plumbing: the frontend
# folds it into NIR before executable lowering.
struct ReceiveMaybeSelectAction(T)
  @[TangoInternal]
  def initialize(@channel : Channel(T))
  end

  @[TangoInternal]
  def sample : T?
    x = uninitialized T?
    x
  end
end

# Marker for one `select` arm. `sample` types the arm's received value; the
# tuple of samples is the value union Crystal casts each arm back out of.
struct SelectAction(T)
  @[TangoInternal]
  def initialize(@channel : Channel(T))
  end

  @[TangoInternal]
  def sample : T
    x = uninitialized T
    x
  end
end

struct Tuple
  @[Primitive(:tuple_indexer_known_index)]
  def [](index : Int32)
  end

  # The value slot of `Channel.select`: `typeof` over every arm's sample — their
  # union. Only its type matters; the value never materializes.
  @[TangoInternal]
  def tango_select_sample
    {% begin %}
      x = uninitialized typeof({% for i in 0...T.size %}{% if i > 0 %}, {% end %}self[{{i}}].sample{% end %})
      x
    {% end %}
  end
end

@[GoType("sync.Mutex", :pointer)]
class Mutex
  @[Primitive(:tango_mutex_new)]
  def self.new : Mutex
  end

  @[Primitive(:tango_external)]
  @[Go(".Lock")]
  def lock : Nil
  end

  @[Primitive(:tango_external)]
  @[Go(".Unlock")]
  def unlock : Nil
  end

  def synchronize(& : -> Nil) : Nil
    lock
    begin
      yield
    ensure
      unlock
    end
  end
end
