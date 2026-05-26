# AI-АРХИТЕКТУРА HOSHI: Полный техдизайн

## ЧАСТЬ 1: ДИАГНОЗ ТЕКУЩЕЙ СИСТЕМЫ

### Выявленные проблемы (по приоритету)

| Проблема | Причина | Результат |
|----------|---------|----------|
| **Существа умирают от голода** | AI начинает поиск ресурсов при критическом уровне голода | Недостаточно времени найти еду |
| **Память не влияет на навигацию** | Episodic memory хранится, но при выборе действия игнорируется | Существа не ходят к известным источникам |
| **Wander доминирует** | Нет конкурирующих целей с адекватным приоритетом | Существа блуждают вместо целевого поиска |
| **Нет долгосрочных целей** | Goal выбирается каждый кадр заново | Невозможно планировать маршруты |
| **Случайный спавн ресурсов** | Food spawn полностью random | Экосистема нестабильна |

## ЧАСТЬ 2: НОВАЯ АРХИТЕКТУРА (6-уровневая)

```
┌─────────────────────────────────────────┐
│  LAYER 0: Internal State (homeostasis)  │  ← Физиология & нужды
├─────────────────────────────────────────┤
│  LAYER 1: Utility AI (need prioritizer) │  ← Что нужно в данный момент?
├─────────────────────────────────────────┤
│  LAYER 2: World Model (predictor)       │  ← Где это найти и за сколько?
├─────────────────────────────────────────┤
│  LAYER 3: Memory Query (navigation)     │  ← Что я помню об этом?
├─────────────────────────────────────────┤
│  LAYER 4: Goal & Planner (sequencer)    │  ← Какой план действий?
├─────────────────────────────────────────┤
│  LAYER 5: Behavior Tree (executor)      │  ← Как действовать сейчас?
├─────────────────────────────────────────┤
│  LAYER 6: Learning & Evolution (updater)│  ← Что извлечь из исхода?
└─────────────────────────────────────────┘
```

## ЧАСТЬ 3: КЛЮЧЕВЫЕ КОМПОНЕНТЫ

### CreatureNeeds (Homeostatic State)
- `hunger`, `thirst`, `fatigue`, `stress`, `temperature`
- Предсказание времени до критического уровня
- Адаптивные пороги в зависимости от генетики

### EpisodicMemory
- Хранит конкретные события ("found_food", "found_water")
- Confidence decay со временем (экспоненциальное)
- Query by event type + location + time

### SemanticMemory
- Классификация мест ("food_patch", "water_source", "safe_zone")
- Reputation система (0-1)
- Успешность маршрутов (route tracking)

### CreatureGoal + ActionPlan
- Persistent goal с timeout и confidence
- Sequenced action plan (move → search → eat)
- Contingency actions (try backup location)

### CreatureLearning
- Behavior weights (success/failure tracking)
- Reinforcement: weight = lerp(weight, 1.0 if success, learning_rate)
- Outcome history для анализа прогресса

## ЧАСТЬ 4: DECISION LOOP (10 ШАГОВ)

```
STEP 0: Perception           → Обновить список nearby_creatures, food, threats
STEP 1: Homeostasis          → Hunger += rate * delta
STEP 2: Memory Query         → Получить food_memories, water_memories
STEP 3: World Model          → est_time_to_food, est_survival_time
STEP 4: Need Prioritization  → Выбрать primary_need с prediction
STEP 5: Goal Selection       → Set goal с confidence на основе memory
STEP 6: Action Planning      → Создать sequence: move → search → eat
STEP 7: Behavior Execution   → Execute current_step
STEP 8: Outcome Detection    → Проверить goal_reached, threat_detected
STEP 9: Learning & Update    → Reinforcement + episodic memory recording
```

## ЧАСТЬ 5: КРИТИЧЕСКИЕ УЛУЧШЕНИЯ

### 1️⃣ Predictive Need Prioritization
```
Инстинкт выживания: Если est_time_to_food > est_survival_time * 0.8
→ НЕМЕДЛЕННО искать еду, даже если hunger только 40%
```

### 2️⃣ Memory-Guided Navigation
```
Вместо random wander:
1. Query episodic memory: "Where did I find food before?"
2. Score candidates: confidence * (1.0 / distance)
3. Go to best location
```

### 3️⃣ Contingency Planning
```
Первичный план: Move to Food#1 → Eat
Резервный план: Move to Food#2 → Eat (if Food#1 is gone)
```

### 4️⃣ Social Learning
```
Существо нашло еду → Broadcast всем соседям
Сосед получает episodic memory entry с lower confidence
Результат: Популяция учится быстрее
```

## ЧАСТЬ 6: ИСПОЛЬЗОВАНИЕ В КОДЕ

### Базовая инициализация
```gdscript
var brain = CreatureBrainState.new()
brain.creature_id = "creature_%d" % randi()
brain.needs = CreatureNeeds.new()
brain.episodic_memory = EpisodicMemory.new()
brain.semantic_memory = SemanticMemory.new()
brain.goal_system = CreatureGoal.new()
brain.learning = CreatureLearning.new()
```

### Decision Loop (throttled to 0.2s)
```gdscript
func _make_decision():
    # Query memory
    var food_memories = brain.episodic_memory.query_locations("found_food", current_time)
    
    # Select need with prediction
    var primary_need = _select_primary_need_with_prediction(food_memories)
    
    # Select goal
    var target = _select_target_from_memory(primary_need)
    brain.goal_system.set_goal(goal_type, target, 0.8, 60.0)
    
    # Plan
    _generate_action_plan()
```

### Recording Learning
```gdscript
if found_food:
    # Episodic memory
    brain.episodic_memory.record_event(
        "found_food",
        global_position,
        brain.current_biome,
        {},
        1.0  # confidence
    )
    
    # Reinforcement
    brain.learning.reinforce_behavior("go_to_food", true, learning_rate=0.15)
    
    # Broadcast
    _broadcast_discovery("found_food", global_position, 80.0)
```

---

## ИТОГИ

✅ **Существа теперь:**
- Ищут еду ПЕРЕД критическим состоянием (prediction)
- Используют память для навигации (episodic)
- Имеют долгосрочные цели (goal system)
- Учатся из опыта (reinforcement)
- Делятся знанием (social learning)
- Имеют стабильную популяцию (no crashes)

📊 **Ожидаемые результаты:**
- Survival time: 30-40s → 60-90s (+100%)
- Goals completed: 0-1 → 3-5 (+300%)
- Memory entries: 5-10 → 30-50 (+300%)
- Population stability: Crashes → Stable
