# demo_rpg_character.nim
# Demonstrates reactive game state management using state

import ../src/state
import std/[os, strformat, strutils, times, random]

echo "=== RPG Character System Demo ==="
echo "Demonstrating reactive state management with state"
echo ""

# === Character Stats ===
let playerName = createSignal("Hero")
let currentHP = createSignal(100)
let maxHP = createSignal(100)
let currentMP = createSignal(50)
let maxMP = createSignal(50)
let experience = createSignal(0)
let level = createSignal(1)
let gold = createSignal(50)

# === Computed Stats ===

let isAlive = createComputed(proc(): bool =
  currentHP() > 0
)

let hpPercentage = createComputed(proc(): float =
  if maxHP() == 0: 0.0
  else: (currentHP().float / maxHP().float) * 100.0
)

let mpPercentage = createComputed(proc(): float =
  if maxMP() == 0: 0.0
  else: (currentMP().float / maxMP().float) * 100.0
)

let experienceToNextLevel = createComputed(proc(): int =
  level() * 100  # Each level requires level * 100 XP
)

let canLevelUp = createComputed(proc(): bool =
  isAlive() and experience() >= experienceToNextLevel()
)

let attackPower = createComputed(proc(): int =
  10 + (level() * 5)  # Base 10 + 5 per level
)

let defense = createComputed(proc(): int =
  5 + (level() * 2)  # Base 5 + 2 per level
)

let statusMessage = createComputed(proc(): string =
  if not isAlive():
    "💀 DEAD"
  elif hpPercentage() < 20.0:
    "⚠️  CRITICAL"
  elif hpPercentage() < 50.0:
    "🔶 WOUNDED"
  else:
    "✅ HEALTHY"
)

# === Game State Tracking ===
var combatLog: seq[string] = @[]
var achievements: seq[string] = @[]
var saveCount = 0

# === Effects (Side-effects triggered by state changes) ===

# Effect 1: Combat Logger
let combatLogger = createEffect(proc() =
  let hp = currentHP()
  let maxHp = maxHP()
  let status = statusMessage()
  
  if combatLog.len > 0:  # Skip initial setup
    let logEntry = "[" & now().format("HH:mm:ss") & "] HP: " & $hp & "/" & $maxHp & " - " & status
    combatLog.add(logEntry)
    
    # Keep only last 5 entries
    if combatLog.len > 5:
      combatLog = combatLog[^5..^1]
)

# Effect 2: Level Up Handler
let levelUpHandler = createEffect(proc() =
  if canLevelUp():
    let oldLevel = level()
    level(oldLevel + 1)
    experience(experience() - experienceToNextLevel())
    
    # Restore health and mana on level up
    batch(proc() =
      let hpBonus = 20
      let mpBonus = 10
      maxHP(maxHP() + hpBonus)
      maxMP(maxMP() + mpBonus)
      currentHP(maxHP())
      currentMP(maxMP())
    )
    
    achievements.add("🎉 Reached Level " & $level())
    combatLog.add("⬆️  LEVEL UP! Now level " & $level())
)

# Effect 3: Death Handler
let deathHandler = createEffect(proc() =
  if not isAlive() and combatLog.len > 0:
    combatLog.add("💀 " & playerName() & " has fallen in battle!")
    achievements.add("Survived until level " & $level())
)

# Effect 4: Low Resource Warnings
let resourceWarning = createEffect(proc() =
  let hp = hpPercentage()
  let mp = mpPercentage()
  
  untrack(proc() =  # Don't track combatLog reads
    if hp < 20.0 and hp > 0.0 and combatLog.len > 0:
      # if combatLog[^1].find("CRITICAL HP") == -1:  # Avoid spam
      #   combatLog.add("⚠️  CRITICAL HP! Heal immediately!")
      # Do find above without find()
      if not combatLog[^1].contains("CRITICAL HP"):
        combatLog.add("⚠️  CRITICAL HP! Heal immediately!")
  )
)

# Effect 5: Auto-save on significant events
let autoSave = createEffect(proc() =
  let lvl = level()
  let gld = gold()
  let hp = currentHP()
  
  # Save when level or gold changes
  untrack(proc() =
    if saveCount > 0:  # Skip initial
      echo "💾 [AUTO-SAVE] Game saved at Level " & $lvl & ", Gold: " & $gld & ", HP: " & $hp
    inc saveCount
  )
)

# === Game Actions ===

proc takeDamage(amount: int) =
  let damage = max(0, amount - defense())
  let newHP = max(0, currentHP() - damage)
  currentHP(newHP)
  combatLog.add("⚔️  Took " & $damage & " damage (blocked " & $defense() & ")")

proc heal(amount: int) =
  let newHP = min(maxHP(), currentHP() + amount)
  let healed = newHP - currentHP()
  currentHP(newHP)
  if healed > 0:
    combatLog.add("💚 Healed " & $healed & " HP")

proc gainExperience(amount: int)
proc castSpell(mpCost: int, damage: int) =
  if currentMP() >= mpCost:
    currentMP(currentMP() - mpCost)
    combatLog.add("✨ Cast spell for " & $damage & " damage (-" & $mpCost & " MP)")
    gainExperience(damage * 2)  # Spells give bonus XP
  else:
    combatLog.add("❌ Not enough MP! Need " & $mpCost & ", have " & $currentMP())

proc gainExperience(amount: int) =
  experience(experience() + amount)
  combatLog.add("⭐ Gained " & $amount & " XP")

proc lootGold(amount: int) =
  gold(gold() + amount)
  combatLog.add("💰 Looted " & $amount & " gold")

proc displayStatus() =
  echo ""
  echo "┌─────────────────────────────────────────┐"
  echo "│ " & playerName() & " │"
  echo "├─────────────────────────────────────────┤"
  echo "│ Level: " & $level() & "  Status: " & $statusMessage() & "│"
  echo "│ HP: " & $currentHP() & "/" & $maxHP() & " (" & $hpPercentage() & "%) [" & "█".repeat(int(hpPercentage()/10)) & "]│"
  echo "│ MP: " & $currentMP() & "/" & $maxMP() & " (" & $mpPercentage() & "%) [" & "█".repeat(int(mpPercentage()/10)) & "]│"
  echo "│ XP: " & $experience() & "/" & $experienceToNextLevel() & "                            │"
  echo "│ Gold: " & $gold() & "                            │"
  echo "│ Attack: " & $attackPower() & "  Defense: " & $defense() & "               │"
  echo "└─────────────────────────────────────────┘"
  
  if combatLog.len > 0:
    echo ""
    echo "Recent Combat Log:"
    for entry in combatLog:
      echo "  ", entry
  
  if achievements.len > 0:
    echo ""
    echo "Achievements:"
    for achievement in achievements[max(0, achievements.len - 3)..^1]:
      echo "  ", achievement

# === Simulation ===

echo "Starting adventure..."
displayStatus()

echo "\n=== Battle Sequence ==="
sleep(500)

# Combat simulation showing reactive updates
takeDamage(15)
sleep(300)
displayStatus()

takeDamage(20)
sleep(300)
displayStatus()

heal(30)
sleep(300)
displayStatus()

gainExperience(50)
lootGold(25)
sleep(300)
displayStatus()

castSpell(15, 40)
sleep(300)
displayStatus()

takeDamage(30)
sleep(300)
displayStatus()

gainExperience(60)  # Should trigger level up!
sleep(500)
displayStatus()

echo "\n=== Testing Batched Updates ==="
batch(proc() =
  gainExperience(50)
  lootGold(100)
  heal(20)
  castSpell(10, 25)
)
sleep(300)
displayStatus()

echo "\n=== Boss Battle! ==="
takeDamage(40)
sleep(300)
castSpell(20, 60)
sleep(300)
takeDamage(35)
sleep(300)
displayStatus()

gainExperience(150)  # Big XP gain from boss
lootGold(500)
sleep(500)
displayStatus()

echo "\n=== Testing Critical Damage ==="
takeDamage(maxHP() - 10)  # Leave at very low HP
sleep(500)
displayStatus()

heal(50)
sleep(300)
displayStatus()

echo "\n=== Final Stats ==="
displayStatus()

echo ""
echo "=== Achievements Unlocked ==="
for achievement in achievements:
  echo "  ", achievement

# Cleanup
dispose(combatLogger)
dispose(levelUpHandler)
dispose(deathHandler)
dispose(resourceWarning)
dispose(autoSave)

echo ""
echo "Demo complete! All reactive effects properly triggered."
echo "Total auto-saves: " & $saveCount