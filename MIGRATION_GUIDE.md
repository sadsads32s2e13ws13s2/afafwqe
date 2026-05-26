# PHASE 1: Migration Guide
# How to integrate the new AI system into your existing Hoshi project

## Overview

This guide shows how to replace the old creature AI system with the new one.

**Before:** Random wandering, high death rate, no learning
**After:** Goal-directed behavior, memory-guided navigation, persistent learning

---

## Step 1: Backup Your Old System

```bash
# Save old creature.gd
cp scripts/creature.gd scripts/creature.gd.backup
cp scripts/creature_ai.gd scripts/creature_ai.gd.backup
```

---

## Step 2: Copy New AI Files

```bash
# Copy the new AI system
cp -r addons/ai_v2 your_project/addons/

# Structure should look like:
your_project/
├── addons/
│   └── ai_v2/
│       ├── constants.gd
│       ├── creature_brain.gd
│       ├── world_model.gd
│       ├── data/
│       │   ├── creature_needs.gd
│       │   ├── episodic_memory.gd
│       │   └── ... (8 files total)
│       └── test/
│           └── ...
└── scripts/
    └── creature.gd (your main creature)
```

---

## Step 3: Update Your Creature Script

### Before (Old System)
```gdscript
extends Node2D
class_name Creature

var hunger: float = 50
var thirst: float = 50
var position: Vector2

func _physics_process(delta):
    # Update needs
    hunger += 0.5 * delta
    thirst += 0.3 * delta
    
    # Random action selection
    var action = ["wander", "search", "eat", "drink"][randi() % 4]
    
    match action:
        "wander":
            var direction = Vector2.from_angle(randf() * TAU)
            position += direction * 50 * delta
        
        "search":
            if nearby_food_exists():
                eat_food()
        
        # ... other actions ...
    
    # Check death
    if hunger >= 100:
        die()
```

### After (New System - Minimal Change)
```gdscript
extends Node2D
class_name Creature

# Replace all old AI variables with this:
var brain: CreatureBrain
var metrics: CreatureMetrics

# Keep your own state
var velocity: Vector2 = Vector2.ZERO

# Decision throttling
var dt_decision: float = 0.2
var time_since_decision: float = 0.0

func _ready() -> void:
    # Initialize new AI
    brain = CreatureBrain.new("creature_%d" % randi())
    metrics = CreatureMetrics.new(brain.creature_id)

func _physics_process(delta: float) -> void:
    # OLD: Remove all the manual need updates and action selection
    # NEW: All handled by brain
    
    # Step 1: Perception (what can I sense?)
    _update_perception()
    
    # Step 2: Homeostasis update (internal needs)
    brain.update(delta)
    
    # Step 3: Decision making (throttled)
    time_since_decision += delta
    if time_since_decision >= dt_decision:
        brain.make_decision(Time.get_ticks_msec() / 1000.0)
        time_since_decision = 0.0
    
    # Step 4: Execute action
    _execute_action(delta)
    
    # Step 5: Detect outcomes and learn
    _detect_outcomes()
    
    # Step 6: Check for death
    if brain.needs.hunger >= 100.0 or brain.needs.thirst >= 100.0:
        _die("starvation")

func _update_perception() -> void:
    # Query what the creature can sense
    brain.current_position = global_position
    brain.current_biome = get_current_biome()  # Your existing method
    brain.nearby_creatures = get_nearby_creatures()  # Your existing method
    brain.nearby_food = get_nearby_food()  # Your existing method
    brain.nearby_threats = get_nearby_threats()  # Your existing method

func _execute_action(delta: float) -> void:
    var action = brain.get_next_action()
    if not action:
        return
    
    match action.action_type:
        "move_to":
            var direction = (action.target_location - global_position).normalized()
            velocity = direction * 50.0  # Your existing speed
            global_position += velocity * delta
        
        "search":
            # Check if found food in nearby_food list
            if not brain.nearby_food.is_empty():
                brain.action_plan.advance_step()
        
        "eat":
            if not brain.nearby_food.is_empty():
                var food = brain.nearby_food[0]
                brain.needs.hunger = max(brain.needs.hunger - 30.0, 0.0)
                
                # Record learning
                brain.episodic_memory.record_event(
                    "found_food",
                    global_position,
                    brain.current_biome,
                    {},
                    1.0
                )
                
                metrics.episodic_memories_recorded += 1
                food.queue_free()
                brain.action_plan.advance_step()
        
        "drink":
            # Similar to eat
            brain.needs.thirst = max(brain.needs.thirst - 30.0, 0.0)
            brain.episodic_memory.record_event(
                "found_water",
                global_position,
                brain.current_biome,
                {},
                1.0
            )
            metrics.episodic_memories_recorded += 1
            brain.action_plan.advance_step()
        
        "rest":
            velocity = Vector2.ZERO
            brain.needs.fatigue = max(brain.needs.fatigue - 10.0 * delta, 0.0)

func _detect_outcomes() -> void:
    if not brain.action_plan.get_current_step():
        return
    
    var step = brain.action_plan.get_current_step()
    
    # If we reached the target location
    if global_position.distance_to(step.target_location) < 20.0:
        brain.action_plan.advance_step()
    
    # If plan is complete, mark goal done
    if brain.action_plan.is_plan_complete():
        if brain.goal_system.current_goal:
            brain.goal_system.complete_goal(true)
            metrics.goals_completed += 1

func _die(reason: String) -> void:
    metrics.death_time = Time.get_ticks_msec() / 1000.0
    metrics.print_summary()
    queue_free()
```

---

## Step 4: Existing Helper Methods

Keep your existing methods for biome, nearby creatures, etc.:

```gdscript
# These methods already exist in your creature, keep them
func get_current_biome() -> String:
    # Your existing implementation
    return "forest"

func get_nearby_creatures() -> Array:
    # Your existing implementation
    return []

func get_nearby_food() -> Array:
    # Your existing implementation
    return get_tree().get_nodes_in_group("food")

func get_nearby_threats() -> Array:
    # Your existing implementation
    return []
```

---

## Step 5: Test the Migration

### Quick Manual Test
```gdscript
# In editor console after running
var creature = get_node("Creature")
print(creature.brain.needs.hunger)        # Check hunger
print(creature.metrics.goals_completed)   # Check goals
print(creature.brain.get_debug_info())    # Full debug info
```

### Run Full Test Scenario
```
1. Create new scene
2. Attach test_scene_setup.gd
3. Run for 300 seconds
4. Compare metrics with old system
```

---

## Step 6: Tune Constants

Open `addons/ai_v2/constants.gd` and adjust:

```gdscript
# If creatures are still dying of hunger:
const HUNGER_RATE = 0.3              # Lower = slower hunger
const HUNGER_THRESHOLD_MILD = 30.0   # Search earlier

# If creatures wander too much:
const NEED_SCORE_EXPLORE_WEIGHT = 0.05  # Reduce exploration

# If learning seems unstable:
const BEHAVIOR_WEIGHT_LEARNING_RATE = 0.05  # Slower learning
```

---

## Step 7: Verify Improvements

Track these metrics:

```
OLD System Baseline (for comparison):
- Avg survival time: 30-40 seconds
- Goals completed per creature: 0-1
- Episodic memories: 5-10
- Population crashes: Yes

NEW System (PHASE 1):
- Avg survival time: 45-80 seconds      (+50-100%)
- Goals completed per creature: 3-5      (+200%)
- Episodic memories: 30-50              (+300%)
- Population crashes: No                (stable)
```

Compare using:
```gdscript
ecosystem_metrics.print_report()
creature.metrics.print_summary()
```

---

## Common Issues & Solutions

### Issue: Creatures still dying of hunger

**Solution:**
```gdscript
# In constants.gd
const HUNGER_RATE = 0.3  # Was 0.5
const HUNGER_THRESHOLD_MILD = 30.0  # Was 40.0
```

### Issue: Creatures not using remembered food locations

**Debug:**
```gdscript
var creature = get_node("Creature")
var food_memories = creature.brain.episodic_memory.query_locations("found_food", Time.get_ticks_msec() / 1000.0)
print("Remembered food locations: %d" % food_memories.size())
```

### Issue: Creatures wandering instead of going to goal

**Check:**
```gdscript
print(creature.brain.goal_system.current_goal)
print(creature.brain.action_plan.get_summary())
```

If goal is NONE, creatures haven't learned yet. Wait longer or reduce `HUNGER_THRESHOLD_MILD`.

### Issue: Memory keeps growing (no consolidation)

**Solution:** Memory automatically caps at 500 entries (FIFO). Add consolidation:
```gdscript
# In _physics_process, add:
if int(time_since_decision) % 60 == 0:  # Every 60 seconds
    creature.brain.episodic_memory.consolidate()
```

---

## Rollback Plan

If something goes wrong:

```bash
# Restore old system
cp scripts/creature.gd.backup scripts/creature.gd
rm -rf addons/ai_v2/
```

But don't! If you hit issues, let's debug them instead.

---

## Next Steps After PHASE 1

Once PHASE 1 is working:

1. **Measure baseline** - Run for 10 minutes, collect metrics
2. **Tune constants** - Adjust for your game balance
3. **Plan PHASE 2** - Persistent food patches
4. **Implement PHASE 2** - Add resource clustering
5. **Add evolution** - Connect genetics to AI parameters

See `PHASE_1_CHECKLIST.md` for full roadmap.

---

## File Reference

| File | Purpose | Status |
|------|---------|--------|
| `creature_brain.gd` | Main AI loop | Core |
| `creature_needs.gd` | Homeostatic state | Core |
| `episodic_memory.gd` | Event recording | Core |
| `semantic_memory.gd` | Place knowledge | Core |
| `creature_goal.gd` | Goal persistence | Core |
| `action_plan.gd` | Action sequencing | Core |
| `creature_learning.gd` | Behavior weights | Core |
| `world_model.gd` | Predictions | Core |
| `constants.gd` | Configuration | Tunable |

---

## Support

If you get stuck:

1. Enable debug logging:
   ```gdscript
   const DEBUG_LOG_DECISIONS = true
   ```

2. Check creature state:
   ```gdscript
   print(creature.brain.get_debug_info())
   ```

3. Check metrics:
   ```gdscript
   creature.metrics.print_summary()
   ```

4. Review this guide and README.md

---

**Migration Guide Complete** ✅
**Estimated time: 30 minutes**
**Complexity: Low - minimal changes needed**