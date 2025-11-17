# State - Universal Reactive State Graph

A generic, engine-agnostic reactivity and state-graph system that abstracts the core ideas behind React (diffing, reconciliation, declarative state → side-effects) into a framework-neutral model that can drive *anything*, not just UI rendering.

## Features

- **Universal reactive core** - Use for frontend rendering *and* non-visual domains
- **Signal-based state** - Observable state units that update dependents automatically
- **Computed values** - Derived state that updates efficiently when dependencies change
- **Effects** - Side-effects that run when reactive dependencies update
- **Batched updates** - Optimize performance by batching multiple state changes
- **Automatic dependency tracking** - No manual subscription management needed
- **Multiple contexts** - Isolated reactive graphs that coexist independently
- **Deterministic propagation** - Predictable update ordering
- **Circular dependency detection** - Runtime cycle detection with clear error messages
- **Exception safety** - Graceful error handling with automatic recovery
- **Type-safe** - Full generic support with Nim's type system

## Quick Start
```nim
import state

# Create mutable state (uses default context)
let count = createState(0)
# Or use: createSignal(0)

# Create computed/derived state
let doubled = createComputed(proc(): int = count() * 2)
# Or use: createDerived, createMemo

# Create effects (run when dependencies change)
let watcher = createEffect(proc() =
  echo "Count is now: " & $count()
  echo "Doubled is: " & $doubled()
)

# Update state (triggers effect)
count(5)  # Prints: "Count is now: 5" and "Doubled is: 10"

# Cleanup
dispose(watcher)
```

## Core Concepts

### State/Signals

**Mutable state** that can be read and written:
```nim
let name = createState("Alice")
let age = createState(30)

echo name()  # Read: "Alice"
name("Bob")  # Write: "Bob"

# Update based on current value
age.update(proc(current: int): int = current + 1)
```

### Computed/Derived Values

**Read-only derived state** that automatically updates:
```nim
let firstName = createState("John")
let lastName = createState("Doe")

let fullName = createComputed(proc(): string =
  firstName() & " " & lastName()
)

echo fullName()  # "John Doe"
firstName("Jane")
echo fullName()  # "Jane Doe" - automatically updated!
```

### Effects

**Side-effects** that run when dependencies change:
```nim
let user = createState("guest")

let logEffect = createEffect(proc() =
  echo "Current user: " & user()
)
# Immediately prints: "Current user: guest"

user("admin")
# Prints: "Current user: admin"

dispose(logEffect)  # Stop the effect
```

### Effect Cleanup

Run cleanup code when effect re-runs or is disposed:
```nim
let url = createState("https://api.example.com/users")

let fetchEffect = createEffect(proc() =
  let currentUrl = url()
  echo "Fetching from: " & currentUrl
  
  onCleanup(proc() =
    echo "Canceling previous fetch"
  )
)

url("https://api.example.com/posts")
# Prints:
#   "Canceling previous fetch"
#   "Fetching from: https://api.example.com/posts"
```

## Advanced Usage

### Multiple Contexts

Create isolated reactive graphs that don't interfere with each other:
```nim
# Default context (simple cases)
let globalCount = createState(0)

# Custom contexts (for isolation)
let ctx1 = newContext()
let ctx2 = newContext()

let sig1 = ctx1.createState(10)
let sig2 = ctx2.createState(20)

# These are completely independent
sig1(15)  # Doesn't affect sig2 or globalCount
sig2(25)  # Doesn't affect sig1 or globalCount

# Clean shutdown
dispose(ctx1)
dispose(ctx2)
```

### Context Disposal

Properly clean up contexts when done:
```nim
let ctx = newContext()

let data = ctx.createState(100)
let derived = ctx.createComputed(proc(): int = data() * 2)

let eff = ctx.createEffect(proc() =
  echo "Value: " & $derived()
)

# ... use context ...

dispose(ctx)  # Cleans up all effects, runs cleanup functions

# After disposal:
# - Effects no longer run
# - Signals become inert (reads work, writes are ignored)
# - Cannot create new signals/effects in this context
```

### Batched Updates

Optimize multiple updates:
```nim
let x = createState(0)
let y = createState(0)

let sum = createComputed(proc(): int = x() + y())

let effect = createEffect(proc() =
  echo "Sum: " & $sum()
)

# Without batching: effect runs 3 times
x(1)
y(2)
x(3)

# With batching: effect runs once
batch(proc() =
  x(10)
  y(20)
  x(30)
)
# Only prints once: "Sum: 50"
```

### Peek - Untracked Reads

Read state without creating dependencies:
```nim
let trigger = createState(0)
let data = createState("hello")

let effect = createEffect(proc() =
  discard trigger()  # Tracked - will cause re-runs
  
  echo peek(data)  # NOT tracked - won't cause re-runs
)

data("world")  # Effect doesn't run
trigger(1)     # Effect runs, prints "world"
```

**Use `peek()` when:**
- Reading for logging/debugging
- Conditional reads that shouldn't create dependencies
- One-time initialization values

### Untracked Blocks

Disable dependency tracking temporarily:
```nim
let trigger = createState(0)
let data = createState("hello")

let effect = createEffect(proc() =
  discard trigger()  # Tracked
  
  untrack(proc() =
    echo data()  # NOT tracked
  )
)

data("world")  # Effect doesn't run
trigger(1)     # Effect runs
```

### Conditional Dependencies

Dependencies change based on conditions:
```nim
let mode = createState(true)
let optionA = createState(10)
let optionB = createState(20)

let value = createComputed(proc(): int =
  if mode():
    optionA()  # Only tracked when mode is true
  else:
    optionB()  # Only tracked when mode is false
)

echo value()  # 10
optionB(999)  # Doesn't trigger recomputation
optionA(5)    # Triggers recomputation
```

## API Reference

### Signal Creation
```nim
# Default context
let sig = createSignal(initial)
let state = createState(initial)  # Alias

# Custom context
let ctx = newContext()
let sig = ctx.createSignal(initial)
let state = ctx.createState(initial)  # Alias
```

### Computed Values
```nim
# Default context
let computed = createComputed(proc(): T = ...)
let derived = createDerived(proc(): T = ...)  # Alias
let memo = createMemo(proc(): T = ...)  # Alias

# Custom context
let ctx = newContext()
let computed = ctx.createComputed(proc(): T = ...)
```

### Effects
```nim
# Default context
let eff = createEffect(proc() = ...)
let watcher = createWatcher(proc() = ...)  # Alias

# Custom context
let ctx = newContext()
let eff = ctx.createEffect(proc() = ...)

# Always dispose when done
dispose(eff)
```

### Reading and Writing
```nim
# Call operator syntax
let value = signal()      # Read
signal(newValue)          # Write

# Explicit methods
let value = signal.get()  # Read
signal.set(newValue)      # Write

# Update based on current value
signal.update(proc(old: T): T = ...)

# Peek (read without tracking)
let value = peek(signal)
```

### Batching
```nim
# Default context
batch(proc() =
  signal1(value1)
  signal2(value2)
  # All updates batched together
)

# Custom context
ctx.batch(proc() =
  # ...
)
```

### Untracking
```nim
# Default context
untrack(proc() =
  discard signal()  # Not tracked
)

# Custom context
ctx.untrack(proc() =
  # ...
)
```

### Context Management
```nim
# Create new context
let ctx = newContext()

# Check if disposed
if ctx.isDisposed():
  echo "Context is disposed"

# Get context from signal/effect
let ctx = signal.context()
let ctx = effect.context()

# Dispose context (cleans up everything)
dispose(ctx)

# Reset default context (for testing)
resetDefaultContext()
```

### Debug Utilities
```nim
# Get subscriber count
let count = signal.getSubscriberCount()

# Get dependency count
let count = signal.getDependencyCount()

# Check if computed is dirty
if signal.isDirty():
  echo "Needs recomputation"

# Context statistics
let sigCount = ctx.signalCount()
let effCount = ctx.effectCount()
```

## API Aliases

Multiple naming styles are supported:

| Primary | Aliases | Description |
|---------|---------|-------------|
| `createSignal` | `createState` | Create mutable state |
| `createComputed` | `createDerived`, `createMemo` | Create computed value |
| `createEffect` | `createWatcher` | Create side-effect |

Use whichever naming convention fits your mental model!

## How Dependency Tracking Works

The "magic" of automatic dependency tracking uses **context-based tracking**:

1. When a computed value or effect runs, it becomes the "current consumer" in its context
2. Any signal read during execution registers the current consumer as a dependent
3. When a signal updates, it notifies all its dependents to re-run
```nim
# Under the hood:
let computed = createComputed(proc(): int =
  a() + b()  # Both a.get() and b.get() call trackDependency()
)

# trackDependency() registers:
# - a.subscribers.add(computed)
# - computed.dependencies.add(a)
# (same for b)

# When a changes:
# - Marks all a.subscribers as dirty
# - Queues them for update
```

This pattern is similar to React hooks, Vue 3 Composition API, and Solid.js.

## Error Handling

### Circular Dependencies

The library detects circular dependencies at runtime:
```nim
let a = createComputed(proc(): int = b())
let b = createComputed(proc(): int = a())

try:
  discard a()
except CycleDetectedError:
  echo "Circular dependency detected!"
```

### Exception Safety

Computed signals handle exceptions gracefully:
```nim
let trigger = createState(false)

let computed = createComputed(proc(): int =
  if trigger():
    raise newException(ValueError, "Error!")
  return 42
)

echo computed()  # 42

trigger(true)
try:
  discard computed()  # Throws
except ValueError:
  echo "Caught error"

# Signal is marked dirty, will retry on next read
trigger(false)
echo computed()  # 42 - recovered
```

## Real-World Example
```nim
import state

# Game character stats
let health = createState(100)
let maxHealth = createState(100)
let level = createState(1)

let healthPercent = createComputed(proc(): float =
  (health().float / maxHealth().float) * 100.0
)

let status = createComputed(proc(): string =
  if health() <= 0:
    "DEAD"
  elif healthPercent() < 20.0:
    "CRITICAL"
  elif healthPercent() < 50.0:
    "WOUNDED"
  else:
    "HEALTHY"
)

# Log health changes
let logger = createEffect(proc() =
  echo "HP: " & $health() & "/" & $maxHealth() & " (" & status() & ")"
)

# Auto-level on health threshold
let levelUp = createEffect(proc() =
  if health() >= maxHealth() and level() < 10:
    batch(proc() =
      level(level() + 1)
      maxHealth(maxHealth() + 20)
      health(maxHealth())  # Full heal
    )
    echo "Level up! Now level " & $level()
)

# Simulate combat
health(80)   # "HP: 80/100 (HEALTHY)"
health(15)   # "HP: 15/100 (CRITICAL)"
health(100)  # Triggers level up!

# Cleanup
dispose(logger)
dispose(levelUp)
```

## Performance Considerations

- **Lazy evaluation**: Computed values only recalculate when read
- **Batching**: Use `batch()` for multiple updates to avoid redundant recomputation
- **Dispose effects**: Always dispose effects when done to prevent memory leaks
- **Peek**: Use `peek()` to read values without creating dependencies
- **Context disposal**: Use `dispose(ctx)` to clean up entire graphs at once
- **OrderedSet**: Update queue automatically deduplicates to prevent redundant work

## Architecture Notes

### Thread Safety

Each thread gets its own default context via thread-local storage. Multiple contexts can coexist in the same thread, but:

- ❌ **Cannot share signals between threads**
- ✅ **Each thread is isolated** - no cross-thread interference
- ✅ **No locks needed** - single-threaded reactive graphs

For multi-threaded applications, create separate contexts per thread.

### Memory Management

- **Signals**: Managed by GC, but stay in context table until context disposed
- **Effects**: Must call `dispose(effect)` to clean up reactive graph
- **Contexts**: Call `dispose(ctx)` to clean up all effects and signals at once
- **Automatic**: Effects automatically unsubscribe from signals on cleanup

**Best practice**: Always dispose effects when done, or dispose entire contexts.