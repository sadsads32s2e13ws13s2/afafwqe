# in creature.gd
extends Node2D
class_name Creature

var brain: CreatureBrainState
var dt_decision: float = 0.2  # decision every 200ms
var time_since_decision: float = 0.0

func _physics_process(delta: float) -> void:
	# STEP 0: Perception (every frame)
	_update_perception()
	
	# STEP 1: Homeostatic Update (every frame)
	_update_homeostasis(delta)
	
	# STEP 2-9: Decision making (throttled)
	time_since_decision += delta
	if time_since_decision >= dt_decision:
		_make_decision()
		time_since_decision = 0.0
	
	# STEP 7: Execute current action (every frame)
	_execute_action(delta)
	
	# Check for death
	if brain.needs.hunger >= 100.0 or brain.needs.thirst >= 100.0:
		_die("starvation")

func _update_perception() -> void:
	var vision_range = 50.0 * (1.0 + brain.genetics.search_radius_modifier)
	var space_state = get_world_2d().direct_space_state
	
	# Update nearby creatures
	var shape_query = PhysicsShapeQueryParameters2D.new()
	shape_query.shape = CircleShape2D.new()
	shape_query.shape.radius = vision_range
	shape_query.transform = global_transform
	
	var results = space_state.intersect_shape(shape_query)
	brain.nearby_creatures.clear()
	brain.nearby_food.clear()
	brain.nearby_threats.clear()
	
	for result in results:
		var collider = result["collider"]
		if collider is Creature and collider != self:
			brain.nearby_creatures.append(collider)
		elif collider.is_in_group("food"):
			brain.nearby_food.append(collider)
		elif collider.is_in_group("threat"):
			brain.nearby_threats.append(collider)
	
	# Update biome
	var biome_area = get_biome_at(global_position)
	brain.current_biome = biome_area.biome_type if biome_area else "unknown"
	brain.current_position = global_position

func _update_homeostasis(delta: float) -> void:
	# Apply metabolic costs
	brain.needs.hunger += brain.needs.hunger_rate * delta
	brain.needs.thirst += brain.needs.thirst_rate * delta
	
	# Activity modifier (if moving, hunger increases)
	if velocity.length() > 10.0:
		brain.needs.fatigue += 0.5 * delta
	else:
		brain.needs.fatigue -= brain.needs.fatigue_recovery * delta
	
	# Stress from threats
	if not brain.nearby_threats.is_empty():
		brain.needs.stress += 2.0 * delta
	else:
		brain.needs.stress -= brain.needs.stress_recovery * delta
	
	# Clamp values
	brain.needs.hunger = clamp(brain.needs.hunger, 0.0, 100.0)
	brain.needs.thirst = clamp(brain.needs.thirst, 0.0, 100.0)
	brain.needs.fatigue = clamp(brain.needs.fatigue, 0.0, 100.0)
	brain.needs.stress = clamp(brain.needs.stress, 0.0, 100.0)
	
	# Update predicted survival
	brain.needs.update_predicted_survival(_get_world_model())

func _make_decision() -> void:
	# STEP 2: Query memory
	var food_memories = brain.episodic_memory.query_locations("found_food", _current_time())
	var water_memories = brain.episodic_memory.query_locations("found_water", _current_time())
	
	# STEP 3: World model
	var world_model = _get_world_model()
	var est_time_to_food = world_model.estimate_time_to_nearest_food()
	var est_survival_time = brain.needs.predicted_survival_seconds
	
	# STEP 4: Prioritize needs (IMPROVED with prediction)
	var primary_need = _select_primary_need_with_prediction(est_time_to_food, est_survival_time)
	
	# STEP 5: Select goal
	_select_goal(primary_need, food_memories, water_memories, world_model)
	
	# STEP 6: Plan
	_generate_action_plan()

# ============================================================================
# NEW: Improved need selection with predictive analysis
# ============================================================================

func _select_primary_need_with_prediction(est_time_to_food: float, est_survival_time: float) -> String:
	"""
	CRITICAL FIX: Don't wait until hunger is critical.
	If predicted time to food > time to survival, START HUNTING IMMEDIATELY.
	"""
	
	# SURVIVAL INSTINCT: If in critical danger, ignore everything
	if brain.needs.hunger >= brain.needs.hunger_threshold_critical:
		return "hunger"
	
	if brain.needs.thirst >= 80.0:
		return "thirst"
	
	# PREDICTIVE PLANNING: Check if we will starve before finding food
	# If survival_time (300 sec) < time_to_food (400 sec): DANGER
	if est_time_to_food > est_survival_time * 0.8:  # 80% safety margin
		print_debug("%s: DANGER! Food time %.1fs > survival time %.1fs" % 
		           [brain.creature_id, est_time_to_food, est_survival_time])
		return "hunger"
	
	# Otherwise, use standard utility scoring
	var need_scores: Dictionary = {
		"hunger": _score_need_improved("hunger", est_time_to_food, est_survival_time),
		"thirst": _score_need_improved("thirst", 0.0, 0.0),
		"fatigue": _score_need_improved("fatigue", 0.0, 0.0),
		"social": _score_need_improved("social", 0.0, 0.0),
		"explore": _score_need_improved("explore", 0.0, 0.0)
	}
	
	var max_need = "explore"
	var max_score = 0.0
	for need_name in need_scores:
		if need_scores[need_name] > max_score:
			max_score = need_scores[need_name]
			max_need = need_name
	
	return max_need

func _score_need_improved(need_name: String, est_time_to_food: float, est_survival_time: float) -> float:
	"""
	Improved utility scoring with prediction & intelligence bonus.
	"""
	var urgency = 0.0
	var recent_success_penalty = 0.0
	
	match need_name:
		"hunger":
			# Base urgency from current hunger level
			urgency = (brain.needs.hunger / 100.0)
			
			# Time-to-critical prediction bonus
			var time_to_critical = (brain.needs.hunger_threshold_critical - brain.needs.hunger) / \
			                       brain.needs.hunger_rate
			
			# If we're running out of time, boost urgency
			if est_time_to_food > time_to_critical * 0.7:
				urgency *= 1.5  # 50% urgency boost for time pressure
			
			# Intelligence bonus: smart creatures start searching earlier
			var intelligence_bonus = 1.0 + brain.genetics.intelligence_modifier * 0.5
			urgency *= intelligence_bonus
			
			# Recent success penalty: if we found food recently, don't search again immediately
			var recent_food = brain.episodic_memory.query_locations("found_food", _current_time())
			if not recent_food.is_empty():
				# But only if confidence is still high
				var best_memory = recent_food[0]
				if best_memory.confidence_decay(_current_time()) > 0.5:
					recent_success_penalty = 0.3
		
		"thirst":
			urgency = (brain.needs.thirst / 100.0)
			urgency *= (1.0 + brain.genetics.intelligence_modifier * 0.3)
		
		"fatigue":
			urgency = (brain.needs.fatigue / 100.0)
			# Only rest when moderately tired (not critical)
			if brain.needs.fatigue < 30.0:
				urgency *= 0.5
		
		"social":
			# Social need depends on personality AND presence of creatures
			urgency = (brain.personality.sociability / 100.0)
			if brain.nearby_creatures.is_empty():
				urgency *= 0.3  # Less attractive without companions
			else:
				urgency *= 1.2  # Boost if creatures nearby
		
		"explore":
			# Curiosity driven, but only when survival needs are met
			var survival_safety = 1.0 - (brain.needs.hunger / 100.0)
			urgency = survival_safety * brain.genetics.curiosity_modifier * 0.2
	
	return max(urgency - recent_success_penalty, 0.0)

# ============================================================================
# IMPROVED: Goal selection with memory-based navigation
# ============================================================================

func _select_goal(primary_need: String, 
                  food_memories: Array[EpisodicMemory.MemoryEntry],
                  water_memories: Array[EpisodicMemory.MemoryEntry],
                  world_model: WorldModel) -> void:
	
	var target: Vector2 = Vector2.ZERO
	var goal_type: CreatureGoal.GoalType
	var confidence: float = 0.5
	var timeout: float = 60.0
	
	match primary_need:
		"hunger":
			goal_type = CreatureGoal.GoalType.FIND_FOOD
			
			# STRATEGY 1: Use episodic memory (most reliable)
			if not food_memories.is_empty():
				# Find best remembered location (high confidence + near)
				target = _select_best_memory_target(food_memories)
				confidence = 0.85
				timeout = 120.0  # Long timeout since we trust this memory
				print_debug("%s: Using remembered food location at %s" % [brain.creature_id, target])
			
			# STRATEGY 2: Use semantic memory (places we've categorized)
			elif brain.semantic_memory.places.size() > 0:
				var food_places = brain.semantic_memory.get_places_by_type("food_patch")
				if not food_places.is_empty():
					# Pick the place with best reputation
					food_places.sort_custom(func(a, b): return a.reputation > b.reputation)
					target = food_places[0].location
					confidence = 0.7 * food_places[0].reputation
					timeout = 90.0
					print_debug("%s: Using semantic memory (reputation: %.2f)" % [brain.creature_id, food_places[0].reputation])
			
			# STRATEGY 3: Expand search radius intelligently
			else:
				# Smart creatures search farther, desperate creatures search wider
				var search_radius = 40.0 * (1.0 + brain.genetics.search_radius_modifier)
				search_radius *= (1.0 + brain.needs.hunger / 150.0)  # Expand radius when desperate
				target = global_position + Vector2.from_angle(randf() * TAU) * search_radius
				confidence = 0.2
				timeout = 45.0
				print_debug("%s: Exploring for food (search radius: %.1f)" % [brain.creature_id, search_radius])
		
		"thirst":
			goal_type = CreatureGoal.GoalType.FIND_WATER
			if not water_memories.is_empty():
				target = _select_best_memory_target(water_memories)
				confidence = 0.85
				timeout = 120.0
			else:
				var water_places = brain.semantic_memory.get_places_by_type("water_source")
				if not water_places.is_empty():
					water_places.sort_custom(func(a, b): return a.reputation > b.reputation)
					target = water_places[0].location
					confidence = 0.7 * water_places[0].reputation
					timeout = 90.0
				else:
					target = global_position + Vector2.from_angle(randf() * TAU) * 50.0
					confidence = 0.2
					timeout = 45.0
		
		"fatigue":
			goal_type = CreatureGoal.GoalType.REST
			var safe_zones = brain.semantic_memory.get_places_by_type("safe_zone")
			if not safe_zones.is_empty():
				target = safe_zones[0].location
				confidence = 0.7
				timeout = 30.0  # Short timeout for rest
			else:
				target = global_position
				confidence = 0.5
				timeout = 20.0
		
		"social":
			goal_type = CreatureGoal.GoalType.SOCIAL
			if not brain.nearby_creatures.is_empty():
				# Move towards nearest creature
				brain.nearby_creatures.sort_custom(func(a, b):
					return global_position.distance_to(a.global_position) < \
					       global_position.distance_to(b.global_position)
				)
				target = brain.nearby_creatures[0].global_position
				confidence = 0.9
				timeout = 30.0
			else:
				# Move towards last known creature location
				target = global_position + Vector2.from_angle(randf() * TAU) * 40.0
				confidence = 0.3
				timeout = 45.0
		
		_:  # explore
			goal_type = CreatureGoal.GoalType.EXPLORE
			target = global_position + Vector2.from_angle(randf() * TAU) * 60.0
			confidence = 0.4
			timeout = 60.0
	
	brain.goal_system.set_goal(goal_type, target, 0.8, timeout, confidence)

func _select_best_memory_target(memories: Array[EpisodicMemory.MemoryEntry]) -> Vector2:
	"""
	Pick the best remembered location based on:
	- Confidence decay (fresher memories = better)
	- Distance (closer = faster)
	"""
	if memories.is_empty():
		return global_position
	
	var best_memory = memories[0]
	var best_score = _score_memory_target(best_memory)
	
	for memory in memories.slice(1):
		var score = _score_memory_target(memory)
		if score > best_score:
			best_score = score
			best_memory = memory
	
	return best_memory.location

func _score_memory_target(memory: EpisodicMemory.MemoryEntry) -> float:
	"""
	Score = confidence * distance_factor
	Prefer: high confidence + reasonable distance
	"""
	var confidence = memory.confidence_decay(_current_time())
	var distance = global_position.distance_to(memory.location)
	
	# Discount for very far memories
	var distance_factor = 1.0 / (1.0 + distance / 200.0)
	
	return confidence * distance_factor

# ============================================================================
# IMPROVED: Action planning with contingency
# ============================================================================

func _generate_action_plan() -> void:
	var plan = ActionPlan.new()
	plan.plan_created_time = _current_time()
	
	if brain.goal_system.current_goal:
		var target = brain.goal_system.current_goal.target_location
		var distance = global_position.distance_to(target)
		var speed = 50.0  # pixels/sec
		var est_time = distance / speed
		
		# Always add movement to target
		plan.add_step("move_to", target, est_time)
		
		# Add goal-specific actions with contingency
		match brain.goal_system.current_goal.goal_type:
			CreatureGoal.GoalType.FIND_FOOD:
				plan.add_step("search", target, 5.0)
				plan.add_step("eat", target, 2.0)
				
				# CONTINGENCY: If this doesn't work, try nearby location
				var food_memories = brain.episodic_memory.query_locations("found_food", _current_time())
				if food_memories.size() > 1:
					var backup_target = food_memories[1].location
					var backup_distance = global_position.distance_to(backup_target)
					plan.add_step("move_to", backup_target, backup_distance / speed)
					plan.add_step("search", backup_target, 5.0)
					plan.add_step("eat", backup_target, 2.0)
			
			CreatureGoal.GoalType.FIND_WATER:
				plan.add_step("search", target, 5.0)
				plan.add_step("drink", target, 2.0)
			
			CreatureGoal.GoalType.REST:
				plan.add_step("rest", target, 10.0)
			
			CreatureGoal.GoalType.SOCIAL:
				plan.add_step("move_to", target, est_time)
				plan.add_step("wait", target, 5.0)  # Stand nearby
			
			CreatureGoal.GoalType.EXPLORE:
				plan.add_step("move_to", target, est_time)
				plan.add_step("observe", target, 3.0)
	
	brain.action_plan = plan

func _execute_action(delta: float) -> void:
	var step = brain.action_plan.get_current_step()
	if not step:
		return
	
	match step.action_type:
		"move_to":
			var direction = (step.target_location - global_position).normalized()
			velocity = direction * 50.0  # speed
			position += velocity * delta
		
		"search":
			# Check if found food
			if not brain.nearby_food.is_empty():
				brain.action_plan.advance_step()
		
		"eat":
			# Consume nearby food
			if not brain.nearby_food.is_empty():
				var food = brain.nearby_food[0]
				brain.needs.hunger = max(brain.needs.hunger - 20.0, 0.0)
				
				# Record success
				brain.learning.record_outcome(
					"find_food", true, 20.0,
					{"location": global_position, "biome": brain.current_biome}
				)
				
				# Record memory
				brain.episodic_memory.record_event(
					"found_food", global_position, brain.current_biome,
					{"food_type": "standard"},
					1.0
				)
				
				# Broadcast to nearby creatures
				_broadcast_discovery("found_food", global_position, 80.0)
				
				food.queue_free()
				brain.action_plan.advance_step()
		
		"drink":
			if not brain.nearby_water.is_empty():
				var water = brain.nearby_water[0]
				brain.needs.thirst = max(brain.needs.thirst - 20.0, 0.0)
				brain.learning.record_outcome(
					"find_water", true, 20.0,
					{"location": global_position, "biome": brain.current_biome}
				)
				brain.episodic_memory.record_event(
					"found_water", global_position, brain.current_biome,
					{},
					1.0
				)
				_broadcast_discovery("found_water", global_position, 70.0)
				water.queue_free()
				brain.action_plan.advance_step()
		
		"rest":
			brain.needs.fatigue = max(brain.needs.fatigue - 5.0 * delta, 0.0)
			velocity = Vector2.ZERO
		
		"wait":
			velocity = Vector2.ZERO
			# Just stand still
		
		"observe":
			velocity = Vector2.ZERO
			# Check for discoveries
			if not brain.nearby_food.is_empty():
				brain.episodic_memory.record_event(
					"found_food", global_position, brain.current_biome,
					{},
					0.6  # Lower confidence since just observed
				)

func _broadcast_discovery(event_type: String, location: Vector2, quality: float) -> void:
	"""
	Creature found something good → tell nearby friends (SOCIAL LEARNING)
	"""
	var broadcast_range = 80.0 * (1.0 + brain.personality.sociability / 100.0)
	
	for nearby_creature in brain.nearby_creatures:
		var distance = global_position.distance_to(nearby_creature.global_position)
		if distance > broadcast_range:
			continue
		
		# Transmission probability based on sociability
		var transmission_chance = 0.5 + \
		                         brain.personality.sociability / 200.0 + \
		                         nearby_creature.brain.genetics.intelligence_modifier * 0.2
		
		if randf() < transmission_chance:
			nearby_creature.brain.episodic_memory.record_event(
				event_type,
				location,
				brain.current_biome,
				{"learned_from": brain.creature_id},
				quality / 100.0
			)
			print_debug("%s learned about %s from %s" % 
			           [nearby_creature.brain.creature_id, event_type, brain.creature_id])

func _current_time() -> float:
	return Time.get_ticks_msec() / 1000.0

func _get_world_model() -> WorldModel:
	# Simplified: query GameManager for current resource distribution
	return GameManager.world_model

func _die(reason: String) -> void:
	print_debug("%s died from %s" % [brain.creature_id, reason])
	queue_free()