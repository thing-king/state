# state.nim
# A universal reactive state graph system

import std/[tables, sets, sequtils, hashes]
export tables, sets, sequtils, hashes

type
  SignalId = distinct int
  
  EffectProc = proc() {.closure.}
  ComputeProc[T] = proc(): T {.closure.}
  
  SignalKind = enum
    skSource      # Mutable state signal
    skComputed    # Derived from other signals
  
  # Base type that holds the subscription graph
  SignalBase* = ref object of RootObj
    id: SignalId
    ctx: StateContext
    subscribers: HashSet[SignalId]
    dependencies: HashSet[SignalId]
    kind: SignalKind
    dirty: bool
  
  # Generic signal with typed value
  Signal*[T] = ref object of SignalBase
    value: T
    compute: ComputeProc[T]

  EffectSignal* = ref object
    id: SignalId
    ctx: StateContext
    effect: EffectProc
    dependencies: HashSet[SignalId]
    cleanup: EffectProc
    dirty: bool
    disposed: bool

  StateContext* = ref object
    nextId: int
    currentEffect: EffectSignal
    currentComputed: SignalBase
    signalBases: Table[SignalId, SignalBase]
    effects: Table[SignalId, EffectSignal]
    updateQueue: OrderedSet[SignalId]
    effectQueue: OrderedSet[SignalId]
    inBatch: bool
    tracking: bool
    computeStack: seq[SignalId]  # For cycle detection
    disposed: bool

  CycleDetectedError* = object of CatchableError
  ContextDisposedError* = object of CatchableError

# Default global context
var defaultContext {.threadvar.}: StateContext

proc getDefaultContext(): StateContext {.inline.} =
  if defaultContext.isNil:
    defaultContext = StateContext(
      nextId: 0,
      tracking: true,
      signalBases: initTable[SignalId, SignalBase](),
      effects: initTable[SignalId, EffectSignal](),
      updateQueue: initOrderedSet[SignalId](),
      effectQueue: initOrderedSet[SignalId](),
      computeStack: @[],
      disposed: false
    )
  result = defaultContext

proc newContext*(): StateContext =
  ## Creates a new isolated reactive state context.
  ## 
  ## Multiple contexts can coexist independently, each with their own
  ## signals, effects, and state. Useful for:
  ## - Testing (isolated contexts per test)
  ## - Multiple independent reactive graphs
  ## - Scoped state management
  ##
  ## Example:
  ##   let ctx1 = newContext()
  ##   let ctx2 = newContext()
  ##   let sig1 = ctx1.createSignal(10)
  ##   let sig2 = ctx2.createSignal(20)
  ##   # sig1 and sig2 are completely independent
  runnableExamples:
    let ctx = newContext()
    let x = ctx.createSignal(42)
    assert x() == 42
  
  result = StateContext(
    nextId: 0,
    tracking: true,
    signalBases: initTable[SignalId, SignalBase](),
    effects: initTable[SignalId, EffectSignal](),
    updateQueue: initOrderedSet[SignalId](),
    effectQueue: initOrderedSet[SignalId](),
    computeStack: @[],
    disposed: false
  )

proc resetDefaultContext*() =
  ## Reset the default thread-local context. Useful for testing.
  ## 
  ## Note: This does NOT dispose effects/signals. Call dispose() explicitly
  ## before resetting if you need cleanup.
  defaultContext = nil

proc dispose*(ctx: StateContext) =
  ## Dispose a context, cleaning up all effects and marking it as disposed.
  ## 
  ## After disposal:
  ## - All effects are disposed and their cleanup functions run
  ## - No new signals or effects can be created
  ## - Existing signals become inert (reads work, writes do nothing)
  ##
  ## Example:
  ##   let ctx = newContext()
  ##   # ... use context ...
  ##   dispose(ctx)  # Clean shutdown
  if ctx.disposed:
    return
  
  # Dispose all effects
  for effectId, effect in ctx.effects:
    if effect.cleanup != nil:
      try:
        effect.cleanup()
      except:
        discard
  
  ctx.effects.clear()
  ctx.signalBases.clear()
  ctx.updateQueue.clear()
  ctx.effectQueue.clear()
  ctx.disposed = true

proc checkDisposed(ctx: StateContext) {.inline.} =
  if ctx.disposed:
    raise newException(ContextDisposedError, 
      "Cannot use disposed context")

proc `==`*(a, b: SignalId): bool {.borrow.}
proc hash(id: SignalId): Hash {.borrow.}
proc `$`*(id: SignalId): string {.borrow.}

# Core signal creation and management

proc nextId(ctx: StateContext): SignalId {.inline.} =
  checkDisposed(ctx)
  result = SignalId(ctx.nextId)
  inc ctx.nextId

# Context-aware creation
proc createSignal*[T](ctx: StateContext, initial: T): Signal[T] =
  ## Creates a new reactive signal in the given context.
  ## 
  ## Example:
  ##   let ctx = newContext()
  ##   let count = ctx.createSignal(0)
  ##   count(5)
  ##   echo count()  # 5
  result = Signal[T](
    id: nextId(ctx),
    ctx: ctx,
    value: initial,
    subscribers: initHashSet[SignalId](),
    dependencies: initHashSet[SignalId](),
    kind: skSource,
    dirty: false
  )
  ctx.signalBases[result.id] = result

proc createSignal*[T](initial: T): Signal[T] =
  ## Creates a new reactive signal in the default context.
  ## 
  ## Example:
  ##   let count = createSignal(0)
  ##   count(5)
  ##   echo count()  # 5
  getDefaultContext().createSignal(initial)

proc createState*[T](ctx: StateContext, initial: T): Signal[T] =
  ## Alias for createSignal with explicit context
  ctx.createSignal(initial)

proc createState*[T](initial: T): Signal[T] =
  ## Alias for createSignal with default context
  createSignal(initial)

proc createComputed*[T](ctx: StateContext, compute: ComputeProc[T]): Signal[T] =
  ## Creates a computed/derived signal in the given context.
  ##
  ## Example:
  ##   let ctx = newContext()
  ##   let a = ctx.createSignal(10)
  ##   let doubled = ctx.createComputed(proc(): int = a() * 2)
  result = Signal[T](
    id: nextId(ctx),
    ctx: ctx,
    compute: compute,
    subscribers: initHashSet[SignalId](),
    dependencies: initHashSet[SignalId](),
    kind: skComputed,
    dirty: true
  )
  ctx.signalBases[result.id] = result

proc createComputed*[T](compute: ComputeProc[T]): Signal[T] =
  ## Creates a computed/derived signal in the default context.
  ##
  ## Example:
  ##   let a = createSignal(10)
  ##   let doubled = createComputed(proc(): int = a() * 2)
  getDefaultContext().createComputed(compute)

proc createDerived*[T](ctx: StateContext, compute: ComputeProc[T]): Signal[T] =
  ctx.createComputed(compute)

proc createDerived*[T](compute: ComputeProc[T]): Signal[T] =
  createComputed(compute)

proc createMemo*[T](ctx: StateContext, compute: ComputeProc[T]): Signal[T] =
  ctx.createComputed(compute)

proc createMemo*[T](compute: ComputeProc[T]): Signal[T] =
  createComputed(compute)

# Dependency tracking

proc trackDependency(signal: SignalBase) {.inline.} =
  let ctx = signal.ctx
  if ctx.disposed or not ctx.tracking:
    return
  
  # Track for effects
  if ctx.currentEffect != nil:
    let effect = ctx.currentEffect
    signal.subscribers.incl(effect.id)
    effect.dependencies.incl(signal.id)
  
  # Track for computed signals
  if ctx.currentComputed != nil:
    let computed = ctx.currentComputed
    signal.subscribers.incl(computed.id)
    computed.dependencies.incl(signal.id)

proc untrack*(ctx: StateContext, body: proc()) =
  ## Temporarily disable dependency tracking in the given context.
  checkDisposed(ctx)
  let wasTracking = ctx.tracking
  ctx.tracking = false
  try:
    body()
  finally:
    ctx.tracking = wasTracking

proc untrack*(body: proc()) =
  ## Temporarily disable dependency tracking in the default context.
  getDefaultContext().untrack(body)

# Forward declarations
proc flushUpdates(ctx: StateContext)
proc runEffect(effect: EffectSignal)

# Signal value access

proc get*[T](signal: Signal[T]): T =
  ## Get the current value of a signal.
  let ctx = signal.ctx
  
  if ctx.disposed:
    return signal.value
  
  if signal.kind == skComputed and signal.dirty:
    # Cycle detection
    if signal.id in ctx.computeStack:
      let cycle = ctx.computeStack & @[signal.id]
      var cycleStr = "Circular dependency detected: "
      for i, id in cycle:
        if i > 0:
          cycleStr = cycleStr & " -> "
        cycleStr = cycleStr & $id
      raise newException(CycleDetectedError, cycleStr)
    
    # Clear old dependencies
    for depId in signal.dependencies:
      if depId in ctx.signalBases:
        let depSignal = ctx.signalBases[depId]
        depSignal.subscribers.excl(signal.id)
    
    signal.dependencies.clear()
    
    # Set up tracking context
    let prevEffect = ctx.currentEffect
    let prevComputed = ctx.currentComputed
    ctx.currentEffect = nil
    ctx.currentComputed = signal
    
    let prevTracking = ctx.tracking
    ctx.tracking = true
    
    ctx.computeStack.add(signal.id)
    
    try:
      signal.value = signal.compute()
      signal.dirty = false
    except CycleDetectedError:
      raise
    except Exception as e:
      signal.dirty = true
      raise e
    finally:
      ctx.tracking = prevTracking
      ctx.currentEffect = prevEffect
      ctx.currentComputed = prevComputed
      discard ctx.computeStack.pop()
  
  trackDependency(signal)
  result = signal.value

proc set*[T](signal: Signal[T], newValue: T) =
  ## Set a new value for a signal.
  if signal.kind != skSource:
    raise newException(ValueError, "Cannot set computed signal")
  
  let ctx = signal.ctx
  
  if ctx.disposed:
    signal.value = newValue
    return
  
  if signal.value != newValue:
    signal.value = newValue
    
    # Mark subscribers as dirty and queue updates
    for subId in signal.subscribers:
      if subId in ctx.signalBases:
        let sub = ctx.signalBases[subId]
        sub.dirty = true
        ctx.updateQueue.incl(subId)
      elif subId in ctx.effects:
        let effect = ctx.effects[subId]
        effect.dirty = true
        ctx.effectQueue.incl(subId)
    
    if not ctx.inBatch:
      ctx.flushUpdates()

proc update*[T](signal: Signal[T], updater: proc(old: T): T) =
  ## Update signal value based on current value
  signal.set(updater(signal.get()))

proc peek*[T](signal: Signal[T]): T =
  ## Read signal value without tracking dependency.
  ## 
  ## Useful for reading values in effects without creating dependencies.
  ##
  ## Example:
  ##   createEffect(proc() =
  ##     if trigger():
  ##       echo peek(otherSignal)  # Won't re-run when otherSignal changes
  ##   )
  signal.value

# Call operator syntax
{.experimental: "callOperator".}
proc `()`*[T](signal: Signal[T]): T = signal.get()
proc `()`*[T](signal: Signal[T], value: T) = signal.set(value)

# Batching

proc batch*(ctx: StateContext, body: proc()) =
  ## Batch multiple updates together in the given context.
  checkDisposed(ctx)
  let wasInBatch = ctx.inBatch
  ctx.inBatch = true
  
  try:
    body()
  finally:
    ctx.inBatch = wasInBatch
    if not wasInBatch:
      ctx.flushUpdates()

proc batch*(body: proc()) =
  ## Batch multiple updates together in the default context.
  getDefaultContext().batch(body)

proc flushUpdates(ctx: StateContext) =
  if ctx.disposed:
    return
  
  # Propagate dirty flags from computed signals to their subscribers
  while ctx.updateQueue.len > 0:
    let queue = toSeq(ctx.updateQueue)
    ctx.updateQueue.clear()
    
    for sigId in queue:
      if sigId in ctx.signalBases:
        let sig = ctx.signalBases[sigId]
        # Mark all subscribers of this dirty computed as dirty too
        for subId in sig.subscribers:
          if subId in ctx.signalBases:
            let sub = ctx.signalBases[subId]
            if not sub.dirty:
              sub.dirty = true
              ctx.updateQueue.incl(subId)
          elif subId in ctx.effects:
            let effect = ctx.effects[subId]
            if not effect.dirty:
              effect.dirty = true
              ctx.effectQueue.incl(subId)
  
  # Then run effects
  while ctx.effectQueue.len > 0:
    let queue = toSeq(ctx.effectQueue)
    ctx.effectQueue.clear()
    
    for effectId in queue:
      if effectId in ctx.effects:
        let effect = ctx.effects[effectId]
        if effect.dirty and not effect.disposed:
          runEffect(effect)

# Effects

proc runEffect(effect: EffectSignal) =
  let ctx = effect.ctx
  
  if ctx.disposed:
    return
  
  # Run cleanup with exception safety
  if effect.cleanup != nil:
    try:
      effect.cleanup()
    except Exception as e:
      when defined(debug):
        echo "Warning: Cleanup error: " & e.msg
    finally:
      effect.cleanup = nil
  
  # Clear old dependencies
  for depId in effect.dependencies:
    if depId in ctx.signalBases:
      let depSignal = ctx.signalBases[depId]
      depSignal.subscribers.excl(effect.id)
  
  effect.dependencies.clear()
  effect.dirty = false
  
  let prevEffect = ctx.currentEffect
  let prevComputed = ctx.currentComputed
  ctx.currentEffect = effect
  ctx.currentComputed = nil
  
  try:
    effect.effect()
  except CycleDetectedError:
    raise
  except Exception as e:
    effect.dirty = true
    raise e
  finally:
    ctx.currentEffect = prevEffect
    ctx.currentComputed = prevComputed

proc createEffect*(ctx: StateContext, effect: EffectProc): EffectSignal =
  ## Creates a side-effect in the given context.
  checkDisposed(ctx)
  
  result = EffectSignal(
    id: nextId(ctx),
    ctx: ctx,
    effect: effect,
    dependencies: initHashSet[SignalId](),
    dirty: true,
    disposed: false
  )
  ctx.effects[result.id] = result
  
  runEffect(result)

proc createEffect*(effect: EffectProc): EffectSignal =
  ## Creates a side-effect in the default context.
  getDefaultContext().createEffect(effect)

proc createWatcher*(ctx: StateContext, effect: EffectProc): EffectSignal =
  ctx.createEffect(effect)

proc createWatcher*(effect: EffectProc): EffectSignal =
  createEffect(effect)

proc onCleanup*(cleanup: EffectProc) =
  ## Register a cleanup function in the current effect.
  ## Works with both default and custom contexts.
  let ctx = getDefaultContext()
  if ctx.currentEffect != nil:
    ctx.currentEffect.cleanup = cleanup

proc dispose*(effect: EffectSignal) =
  ## Dispose an effect.
  let ctx = effect.ctx
  
  if ctx.disposed or effect.disposed:
    return
  
  if effect.cleanup != nil:
    try:
      effect.cleanup()
    except:
      discard
  
  # Remove from all signal subscribers
  for depId in effect.dependencies:
    if depId in ctx.signalBases:
      let depSignal = ctx.signalBases[depId]
      depSignal.subscribers.excl(effect.id)
  
  effect.disposed = true
  ctx.effects.del(effect.id)

# Debug utilities
proc getSubscriberCount*[T](signal: Signal[T]): int =
  signal.subscribers.len

proc getDependencyCount*[T](signal: Signal[T]): int =
  signal.dependencies.len

proc isDirty*[T](signal: Signal[T]): bool =
  signal.dirty

proc isDisposed*(ctx: StateContext): bool =
  ## Check if a context has been disposed
  ctx.disposed

proc signalCount*(ctx: StateContext): int =
  ## Get the number of active signals in this context
  ctx.signalBases.len

proc effectCount*(ctx: StateContext): int =
  ## Get the number of active effects in this context
  ctx.effects.len

# Convenience: get context from signal
proc context*[T](signal: Signal[T]): StateContext =
  ## Get the context that owns this signal
  signal.ctx

proc context*(effect: EffectSignal): StateContext =
  ## Get the context that owns this effect
  effect.ctx