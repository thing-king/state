# tests/test_state.nim
import ../src/state
import std/strutils

when isMainModule:
  echo "=== Testing State Library ==="
  echo ""
  
  # Test 0: Default context
  block:
    echo "Test 0: Default context"
    let sig = createSignal(10)
    assert sig() == 10
    resetDefaultContext()
    let sig2 = createSignal(20)
    assert sig2() == 20
    echo "  ✓ Default context works"
  
  # Test 1: Multiple contexts
  block:
    echo "Test 1: Multiple contexts"
    let ctx1 = newContext()
    let ctx2 = newContext()
    
    let a = ctx1.createSignal(10)
    let b = ctx2.createSignal(20)
    
    assert a() == 10
    assert b() == 20
    
    # Effects in different contexts are isolated
    var aRuns = 0
    var bRuns = 0
    
    let effA = ctx1.createEffect(proc() =
      discard a()
      inc aRuns
    )
    
    let effB = ctx2.createEffect(proc() =
      discard b()
      inc bRuns
    )
    
    aRuns = 0
    bRuns = 0
    
    a(15)
    assert aRuns == 1
    assert bRuns == 0  # b's effect shouldn't run
    
    b(25)
    assert aRuns == 1  # a's effect shouldn't run again
    assert bRuns == 1
    
    dispose(effA)
    dispose(effB)
    dispose(ctx1)
    dispose(ctx2)
    
    echo "  ✓ Multiple contexts are isolated"
  
  # Test 2: Basic signals
  block:
    echo "Test 2: Basic signals"
    let count = createSignal(0)
    assert count() == 0
    count(5)
    assert count() == 5
    count.update(proc(x: int): int = x + 1)
    assert count() == 6
    
    count.set(10)
    assert count.get() == 10
    echo "  ✓ Basic signal get/set works"
  
  # Test 3: Computed signals
  block:
    echo "Test 3: Computed signals"
    let base = createSignal(10)
    let doubled = createComputed(proc(): int = base() * 2)
    
    assert doubled() == 20
    base(15)
    assert doubled() == 30
    echo "  ✓ Computed signals update automatically"
  
  # Test 4: Diamond dependency
  block:
    echo "Test 4: Diamond dependency"
    let a = createSignal(1)
    let b = createComputed(proc(): int = a() + 10)
    let c = createComputed(proc(): int = a() + 100)
    let d = createComputed(proc(): int = b() + c())
    
    assert d() == 112
    a(2)
    assert d() == 114
    echo "  ✓ Diamond dependencies resolve correctly"
  
  # Test 5: Effects
  block:
    echo "Test 5: Effects"
    let count = createSignal(0)
    var effectRuns = 0
    var lastValue = 0
    
    let eff = createEffect(proc() =
      lastValue = count()
      inc effectRuns
    )
    
    assert effectRuns == 1
    assert lastValue == 0
    
    count(5)
    assert effectRuns == 2
    assert lastValue == 5
    
    dispose(eff)
    count(10)
    assert effectRuns == 2
    echo "  ✓ Effects run on dependency changes"
  
  # Test 6: Batched updates
  block:
    echo "Test 6: Batched updates"
    let a = createSignal(0)
    let b = createSignal(0)
    let sum = createComputed(proc(): int = a() + b())
    var computeCount = 0
    
    let eff = createEffect(proc() =
      discard sum()
      inc computeCount
    )
    
    computeCount = 0
    batch(proc() =
      a(1)
      a(2)
      b(3)
      b(4)
    )
    
    assert computeCount == 1
    assert sum() == 6
    dispose(eff)
    echo "  ✓ Batching deduplicates updates"
  
  # Test 7: Conditional dependencies
  block:
    echo "Test 7: Conditional dependencies"
    let condition = createSignal(true)
    let a = createSignal(10)
    let b = createSignal(20)
    
    let conditional = createComputed(proc(): int =
      if condition():
        a()
      else:
        b()
    )
    
    assert conditional() == 10
    
    var updateCount = 0
    let eff = createEffect(proc() =
      discard conditional()
      inc updateCount
    )
    
    updateCount = 0
    b(25)
    assert updateCount == 0
    
    a(15)
    assert updateCount == 1
    assert conditional() == 15
    
    condition(false)
    assert conditional() == 25
    
    updateCount = 0
    a(100)
    assert updateCount == 0
    
    b(30)
    assert updateCount == 1
    
    dispose(eff)
    echo "  ✓ Conditional dependencies track correctly"
  
  # Test 8: Effect cleanup
  block:
    echo "Test 8: Effect cleanup"
    let sig = createSignal(0)
    var cleanupRan = false
    
    let eff = createEffect(proc() =
      discard sig()
      onCleanup(proc() =
        cleanupRan = true
      )
    )
    
    assert not cleanupRan
    sig(1)
    assert cleanupRan
    
    cleanupRan = false
    dispose(eff)
    assert cleanupRan
    echo "  ✓ Effect cleanup runs correctly"
  
  # Test 9: Untrack
  block:
    echo "Test 9: Untrack"
    let a = createSignal(1)
    let b = createSignal(2)
    
    var runCount = 0
    let eff = createEffect(proc() =
      discard a()
      untrack(proc() =
        discard b()
      )
      inc runCount
    )
    
    runCount = 0
    b(10)
    assert runCount == 0
    
    a(5)
    assert runCount == 1
    
    dispose(eff)
    echo "  ✓ Untrack prevents dependency tracking"
  
  # Test 10: Nested computations
  block:
    echo "Test 10: Nested computations"
    let a = createSignal(2)
    let b = createComputed(proc(): int = a() * 2)
    let c = createComputed(proc(): int = b() * 2)
    let d = createComputed(proc(): int = c() * 2)
    
    assert d() == 16
    a(3)
    assert d() == 24
    echo "  ✓ Nested computations propagate correctly"
  
  # Test 11: Multiple effects on same signal
  block:
    echo "Test 11: Multiple effects"
    let sig = createSignal(0)
    var runs = [0, 0, 0]
    
    let eff1 = createEffect(proc() =
      discard sig()
      inc runs[0]
    )
    let eff2 = createEffect(proc() =
      discard sig()
      inc runs[1]
    )
    let eff3 = createEffect(proc() =
      discard sig()
      inc runs[2]
    )
    
    runs = [0, 0, 0]
    sig(1)
    assert runs == [1, 1, 1]
    
    dispose(eff1)
    dispose(eff2)
    dispose(eff3)
    echo "  ✓ Multiple effects trigger independently"
  
  # Test 12: Circular dependency detection
  block:
    echo "Test 12: Circular dependency detection"
    var caughtCycle = false
    
    try:
      var a, b: Signal[int]
      a = createComputed(proc(): int = 
        if b != nil: b() else: 0
      )
      b = createComputed(proc(): int = a())
      
      discard a()
    except CycleDetectedError:
      caughtCycle = true
    
    assert caughtCycle, "Should detect circular dependency"
    
    resetDefaultContext()
    echo "  ✓ Circular dependencies detected"
  
  # Test 13: Exception safety
  block:
    echo "Test 13: Exception safety"
    let trigger = createSignal(false)
    var computeAttempts = 0
    
    let faultyComputed = createComputed(proc(): int =
      inc computeAttempts
      if trigger():
        raise newException(ValueError, "Intentional error")
      return 42
    )
    
    assert faultyComputed() == 42
    assert computeAttempts == 1
    
    trigger(true)
    var caughtError = false
    try:
      discard faultyComputed()
    except ValueError:
      caughtError = true
    
    assert caughtError
    assert faultyComputed.isDirty
    
    trigger(false)
    assert faultyComputed() == 42
    
    echo "  ✓ Exception safety works"
  
  # Test 14: Context disposal
  block:
    echo "Test 14: Context disposal"
    let ctx = newContext()
    
    let sig = ctx.createSignal(10)
    var effectRuns = 0
    
    let eff = ctx.createEffect(proc() =
      discard sig()
      inc effectRuns
    )
    
    assert effectRuns == 1
    
    dispose(ctx)
    assert ctx.isDisposed()
    
    # After disposal, signals become inert
    sig(20)
    assert effectRuns == 1  # Effect shouldn't run
    assert sig() == 20  # Read still works
    
    echo "  ✓ Context disposal works"
  
  # Test 15: Peek
  block:
    echo "Test 15: Peek (untracked read)"
    let a = createSignal(10)
    let b = createSignal(20)
    
    var runCount = 0
    let eff = createEffect(proc() =
      discard a()
      discard peek(b)  # Untracked read
      inc runCount
    )
    
    runCount = 0
    b(30)
    assert runCount == 0  # Shouldn't trigger
    
    a(15)
    assert runCount == 1
    
    dispose(eff)
    echo "  ✓ Peek doesn't track dependencies"
  
  # Test 16: Debug utilities
  block:
    echo "Test 16: Debug utilities"
    let ctx = newContext()
    
    let sig = ctx.createSignal(0)
    let comp = ctx.createComputed(proc(): int = sig())
    
    assert ctx.signalCount() == 2
    assert ctx.effectCount() == 0
    
    let eff = ctx.createEffect(proc() =
      discard comp()
    )
    
    assert ctx.effectCount() == 1
    assert sig.getSubscriberCount() == 1
    assert comp.getDependencyCount() == 1
    
    dispose(eff)
    dispose(ctx)
    echo "  ✓ Debug utilities work"
  
  # Test 17: Context from signal
  block:
    echo "Test 17: Get context from signal"
    let ctx1 = newContext()
    let ctx2 = newContext()
    
    let sig1 = ctx1.createSignal(10)
    let sig2 = ctx2.createSignal(20)
    
    assert sig1.context() == ctx1
    assert sig2.context() == ctx2
    assert sig1.context() != sig2.context()
    
    dispose(ctx1)
    dispose(ctx2)
    echo "  ✓ Can get context from signal"
  
  # Test 18: Mixed default and custom contexts
  block:
    echo "Test 18: Mixed contexts"
    let defaultSig = createSignal(10)
    
    let ctx = newContext()
    let customSig = ctx.createSignal(20)
    
    var defaultRuns = 0
    var customRuns = 0
    
    let defaultEff = createEffect(proc() =
      discard defaultSig()
      inc defaultRuns
    )
    
    let customEff = ctx.createEffect(proc() =
      discard customSig()
      inc customRuns
    )
    
    defaultRuns = 0
    customRuns = 0
    
    defaultSig(15)
    assert defaultRuns == 1
    assert customRuns == 0
    
    customSig(25)
    assert defaultRuns == 1
    assert customRuns == 1
    
    dispose(defaultEff)
    dispose(customEff)
    dispose(ctx)
    
    echo "  ✓ Default and custom contexts coexist"
  
  # Test 19: Alias functions
  block:
    echo "Test 19: Alias functions"
    let state = createState(10)
    let derived = createDerived(proc(): int = state() * 2)
    let memo = createMemo(proc(): int = state() + 5)
    
    assert state() == 10
    assert derived() == 20
    assert memo() == 15
    
    var watcherRan = false
    let watcher = createWatcher(proc() =
      discard state()
      watcherRan = true
    )
    
    watcherRan = false
    state(20)
    assert watcherRan
    
    dispose(watcher)
    echo "  ✓ Alias functions work"
  
  # Test 20: Complex real-world scenario
  block:
    echo "Test 20: Reactive form validation"
    let username = createSignal("")
    let email = createSignal("")
    let password = createSignal("")
    
    let isUsernameValid = createComputed(proc(): bool =
      username().len >= 3
    )
    
    let isEmailValid = createComputed(proc(): bool =
      let e = email()
      e.contains("@") and e.len > 5
    )
    
    let isPasswordValid = createComputed(proc(): bool =
      password().len >= 8
    )
    
    let isFormValid = createComputed(proc(): bool =
      isUsernameValid() and isEmailValid() and isPasswordValid()
    )
    
    var validationLog: seq[string] = @[]
    
    let eff = createEffect(proc() =
      if isFormValid():
        validationLog.add("Form is valid")
      else:
        validationLog.add("Form is invalid")
    )
    
    assert validationLog[^1] == "Form is invalid"
    
    batch(proc() =
      username("john")
      email("john@example.com")
      password("secure123")
    )
    
    assert isFormValid()
    assert validationLog[^1] == "Form is valid"
    
    password("short")
    assert not isFormValid()
    
    dispose(eff)
    echo "  ✓ Complex reactive validation works"
  
  echo ""
  echo "=== All tests passed! ==="