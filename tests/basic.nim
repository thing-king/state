import ../src/state

let count = createState(0)
let doubled = createComputed(proc(): int = count() * 2)

discard createEffect(proc() = 
  let value = count()
  if value != 0:
    echo doubled()
  else:
    echo "Count is zero"
)
count(5)  # Effect re-runs automatically