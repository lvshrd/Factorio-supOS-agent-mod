--------------------------------------------------------------------------------
-- control.lua -mod for Factorio 2.0
-- This project is based on intellicintegration/Factorio-MQTT-Notify from github.
-- From: Mario Gonsales Ishikawa
-- Modified by lvshrd SUPCON
-- License: Apache License 2.0

-- Tracks existing/new machines, writes a single JSON file "factory_state.json"
-- with production, pollution, fluids, inventory, electric etc.
-- 
-- Key feature: 
-- 1. Scans for existing entities on the first tick after load (if not already
--  scanned) to populate global.assets with old saves' machines.

-- 2. Identify all substation positions to define production area centers.
-- Subsequently, assign a unique 'line_id' to each machine within these defined areas, 
-- corresponding to the respective substation center.
--------------------------------------------------------------------------------
SUBSTATION_RADIUS=9
Target_Chest_Position={-0.5,19.5}
Target_Area={{-18,13},{2,20}}
--------------------------------------------------------------------------------
--- 1) Log all the existing entities only for the first tick
--------------------------------------------------------------------------------
All_entity={}
All_entity.assets={}
local function register_all_type_entity(entity)
  -- Some entity dose not have a unit_number
  All_entity.assets[entity.name] = {
    unit_number            = entity.unit_number,
    name                   = entity.name,
    type                   = entity.type,
    position               = {x = entity.position.x, y = entity.position.y},
    surface                = entity.surface,
    prototype              = entity.prototype,
    orientation            = entity.orientation,
    direction              = entity.direction,
    electric_network_id    = entity.electric_network_id,
  }
  if entity.type == "electric-pole" then
    All_entity.assets[entity.name].electric_network_statistics = entity.electric_network_statistics
  end
end

local function remove_all_type_entity(entity)
  if entity and entity.valid and entity.unit_number then
    All_entity.assets[entity.unit_number] = nil
  end
end

--------------------------------------------------------------------------------
-- 2) Ensure global tables
--------------------------------------------------------------------------------
local function ensure_global_tables()
  if not global then global = {} end
  if not global.assets then global.assets = {} end
  if not global.substations then global.substations = {} end  -- New Added
  if global.scanned == nil then
    global.scanned = false  -- used to mark if we've done our first-tick scanning
  end
end

--------------------------------------------------------------------------------
-- 3) Which entity types do we track?
--------------------------------------------------------------------------------
local TRACKED_TYPES = {
  ["assembling-machine"] = true,
  ["furnace"]            = true,
  ["mining-drill"]       = true,
  ["container"]          = true,
  ["logistic-container"] = true,
  ["car"]                = true,
  ["cargo-wagon"]        = true,
  ["fluid-wagon"]        = true,
  ["locomotive"]         = true,
  ["spider-vehicle"]     = true,
  ["roboport"]           = true,
  ["boiler"]             = true,    -- Added boiler
  ["pump"]               = true,    -- Added pump
  ["generator"]          = true,    -- Added generator (steam engine)
  ["electric-pole"]      = true,    -- Added electric-pole (using substation to center the production line)
}

local function is_tracked_entity(entity)
  return (entity and entity.valid and TRACKED_TYPES[entity.type])
end

--------------------------------------------------------------------------------
-- 4) Register/Remove assets
--------------------------------------------------------------------------------
local function register_asset(entity)
  ensure_global_tables()
  global.assets[entity.unit_number] = {
    unit_number            = entity.unit_number,
    name                   = entity.name,
    type                   = entity.type,
    position               = {x = entity.position.x, y = entity.position.y},

    last_status            = entity.status,
    state_changed_tick     = game.tick,

    production_count       = 0,
    production_last_updated= game.tick,
    last_crafting_progress = 0,

    inventory              = {},
    fluids                 = {},
    pollution              = 0,
    electric               = {},

    entity_ref             = entity
  }
  if entity.type == "electric-pole" then
    -- global.assets[entity.unit_number].electric.electric_network_statistics = entity.electric_network_statistics
    if entity.name == "substation" then
      global.substations[entity.unit_number] = {
        unit_number =     entity.unit_number,
        position =        {x = entity.position.x, y = entity.position.y},
        radius =          SUBSTATION_RADIUS
      }
    end
  end

end

local function remove_asset(entity)
  ensure_global_tables()
  if entity and entity.valid and entity.unit_number then
    global.assets[entity.unit_number] = nil
    if entity.type == "electric-pole" and entity.name == "substation" then
      global.substations[entity.unit_number] = nil
    end
  end
end

--------------------------------------------------------------------------------
-- Assign line_ID for entities
--------------------------------------------------------------------------------
local function assign_line_id(entity_position)
  for _, substation in pairs(global.substations) do
    local dx = math.abs(entity_position.x - substation.position.x)
    local dy = math.abs(entity_position.y - substation.position.y)
    if dx <= substation.radius and dy <= substation.radius then
      return "Line" .. substation.unit_number
    end
  end
  return "Isolated"
end

--------------------------------------------------------------------------------
-- 5) Find existing assets (scan the map)
--------------------------------------------------------------------------------
local function find_existing_assets()
  for _, surface in pairs(game.surfaces) do
    local all_entities = surface.find_entities()
    for _, e in pairs(all_entities) do
      print(all_entities)
-- ----------------------------------
-- try to find all the types of entities
      register_all_type_entity(e)
-- --------------------------------
      if is_tracked_entity(e) then
        register_asset(e)
      end
    end
  end
end

--------------------------------------------------------------------------------
-- 6) on_init: Just ensure tables, no scanning yet
--------------------------------------------------------------------------------
script.on_init(function()
  ensure_global_tables()
end)

--------------------------------------------------------------------------------
-- 7) on_load: We can't call game.* here. We only ensure global tables.
--------------------------------------------------------------------------------
script.on_load(function()
  ensure_global_tables()
end)

--------------------------------------------------------------------------------
-- 8) on_tick: On the FIRST TICK after load, we do a big scan if not done yet
--------------------------------------------------------------------------------
script.on_event(defines.events.on_tick, function(event)
  if not global.scanned then
    ensure_global_tables()
    find_existing_assets()
    global.scanned = true
-------------------------------------------------------------------------------
    local json_str = helpers.table_to_json(All_entity)
    helpers.write_file("All_entity_type.json", json_str, false)
--------------------------------------------------------------------------------
  end
end)


--------------------------------------------------------------------------------
-- 9) Handle newly built or removed entities
--------------------------------------------------------------------------------
local function on_entity_created(event)
  local entity = event.created_entity or event.entity
  if is_tracked_entity(entity) then
    register_asset(entity)
  end
end

local function on_entity_removed(event)
  local entity = event.entity
  if entity and entity.valid then
    remove_asset(entity)
    remove_all_type_entity(entity)
  end
end

script.on_event(defines.events.on_built_entity,        on_entity_created)
script.on_event(defines.events.on_robot_built_entity,  on_entity_created)
script.on_event(defines.events.on_entity_died,         on_entity_removed)
script.on_event(defines.events.on_player_mined_entity, on_entity_removed)
script.on_event(defines.events.on_robot_mined_entity,  on_entity_removed)

--------------------------------------------------------------------------------
-- 10) Tracking logic: production, inventory, status, pollution, fluids
--------------------------------------------------------------------------------
local function track_production(asset)
  local entity = asset.entity_ref
  if not (entity and entity.valid) then return end

  local ok, _ = pcall(function() return entity.crafting_progress end)
  if not ok then return end  -- no crafting_progress for this entity

  local recipe = entity.get_recipe()
  if recipe then
    local current = entity.crafting_progress or 0
    local old = asset.last_crafting_progress or 0

    if old > 0.95 and current < old then
      local products = recipe.products or {}
      if #products > 0 and products[1].amount then
        asset.production_count = asset.production_count + products[1].amount
      else
        asset.production_count = asset.production_count + 1
      end
      asset.production_last_updated = game.tick
    end
    asset.last_crafting_progress = current
  else
    asset.last_crafting_progress = 0
  end
end

local function track_inventory(asset)
  local entity = asset.entity_ref
  if not (entity and entity.valid) then return end

  local inv_data = {}

  local function read_inventory(inv_id, label)
    local inv = entity.get_inventory(inv_id)
    if inv and inv.valid then
      -- read_contents gives us a dictionary {["iron-plate"] = count, ...}
      inv_data[label] = inv.get_contents()
    end
  end

  pcall(function() read_inventory(defines.inventory.chest, "chest") end)
  pcall(function() read_inventory(defines.inventory.assembling_machine_input,  "input") end)
  pcall(function() read_inventory(defines.inventory.assembling_machine_output, "output") end)
  if not entity.type == "assembling-machine" then
    pcall(function() read_inventory(defines.inventory.furnace_source,  "furnace_source") end)
    pcall(function() read_inventory(defines.inventory.furnace_result,  "furnace_result") end)
  end
  if not entity.type == "container" then
    pcall(function() read_inventory(defines.inventory.item_main,       "main") end)
  end
  asset.inventory = inv_data
end

local function track_status(asset)
  local entity = asset.entity_ref
  if not (entity and entity.valid) then return end

  local has_status, new_status = pcall(function() return entity.status end)
  if has_status then
    local old_status = asset.last_status
    if new_status ~= old_status then
      asset.last_status = new_status
      asset.state_changed_tick = game.tick
    end
  end
end

local function track_pollution(asset)
  local entity = asset.entity_ref
  if not (entity and entity.valid) then return end
  local surface = entity.surface
  if surface and surface.valid then
    asset.pollution = surface.get_pollution(entity.position) or 0
  else
    asset.pollution = 0
  end
end

local function track_fluids(asset)
  local entity = asset.entity_ref
  if not (entity and entity.valid) then return end

  local fluidbox_count = #entity.fluidbox
  local fluids = {}
  if fluidbox_count > 0 then
    for i=1, fluidbox_count do
      local fluid = entity.fluidbox[i]
      if fluid then
        table.insert(fluids, {
          name = fluid.name,
          amount = fluid.amount,
          temperature = fluid.temperature
        })
      else
        table.insert(fluids, nil)
      end
    end
  end
  asset.fluids = fluids
end

local function track_electric(asset)
  local entity = asset.entity_ref
  if not (entity and entity.valid) then return end
  if (entity.type=="electric-pole") then
    -- asset.electric.electric_network_statistics = entity.electric_network_statistics
    -- if electrical equipment
  elseif entity.is_connected_to_electric_network() then
    asset.electric = {
      energyUsage = entity.prototype.energy_usage,  -- Power, Watt
      currentEnergy = entity.energy,                -- Storaged energy (J)
    }
  end
end

--------------------------------------------------------------------------------
-- 11) Periodic updates to track data and write JSON
--------------------------------------------------------------------------------
local function update_all_assets()
  ensure_global_tables()
  for _, asset in pairs(global.assets) do
    local e = asset.entity_ref
    if e and e.valid then
      track_production(asset)
      track_inventory(asset)
      track_status(asset)
      track_pollution(asset)
      track_fluids(asset)
      track_electric(asset)
    end
  end
end

local function build_snapshot()
  ensure_global_tables()
  local snapshot = {tick = game.tick, assets = {}}
  for _, asset in pairs(global.assets) do
    local e = asset.entity_ref
    if e and e.valid then
      local line_id = assign_line_id(asset.position) --Assign line_ID
      table.insert(snapshot.assets, {
        unit_number            = asset.unit_number,
        name                   = asset.name,
        type                   = asset.type,
        position               = asset.position,
        line_id                = line_id,  -- New Added

        last_status            = asset.last_status,
        state_changed_tick     = asset.state_changed_tick,

        production_count       = asset.production_count,
        production_last_updated= asset.production_last_updated,

        inventory              = asset.inventory,
        fluids                 = asset.fluids,
        pollution              = asset.pollution,
        electric               = asset.electric,
      })
    end
  end
  return snapshot
end

--------------------------------------------------------------------------------
-- Extra) Check the target production_count and clear before it's full
--------------------------------------------------------------------------------
local function clear_final_product()
  local final_chests = game.surfaces[1].find_entities_filtered{area = Target_Area, name = "steel-chest"}
  for _, final_chest in pairs(final_chests) do
    local final_inventory = final_chest.get_inventory(defines.inventory.chest)
    if final_inventory == nil then
      return
    end
    if final_inventory.is_full() then
      final_inventory.clear()
      game.print("Cleared the final area product")
    end
  end
end

local function write_snapshot_to_file()
  local snapshot = build_snapshot()
  local json_str = helpers.table_to_json(snapshot)
  helpers.write_file("factory_state.json", json_str, false)
end

local SNAPSHOT_INTERVAL = 60  -- e.g. every 60 ticks = 1 second
script.on_nth_tick(SNAPSHOT_INTERVAL, function()
  update_all_assets()
  write_snapshot_to_file()
  clear_final_product()
end)
