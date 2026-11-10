__CREATE_SCOPE( "__zspawner", "ZSpawner", null, "ZSpawnerThink" )

Include( "zombies/zombie_generic", this )

ZSpawner.VALID_SPAWN_COLLECTION_PER_THINK <- 25
ZSpawner.VALID_SPAWN_COLLECTION_DELAY     <- 7.0

ZSpawner.MaxZombies <- 50
ZSpawner.CurZombies <- 0

ZSpawner.MinSpawnDistance <- 256.0
ZSpawner.MaxSpawnDistance <- 2048.0

ZSpawner.Paused                <- false
ZSpawner.CollectingSpawnPoints <- false
ZSpawner.ValidSpawnPoints      <- {}

function ZSpawner::_OnDestroy() {

    EntFire( "__z_*", "Kill" )
}

function ZSpawner::Pause()  { Paused = true }
function ZSpawner::Resume() { Paused = false }
function ZSpawner::SetMaxZombies( max ) { MaxZombies = max }
function ZSpawner::SetMinSpawnDistance( min ) { MinSpawnDistance = min }
function ZSpawner::SetMaxSpawnDistance( max ) { MaxSpawnDistance = max }

function ZSpawner::GetValidSpawnPoints() {

    ValidSpawnPoints.clear()

    if ( CollectingSpawnPoints )
        yield true

    CollectingSpawnPoints = true

    local areas     = {}
    local raw_areas = {}

    foreach( i, player in ZUtil.PlayerTables.Survivors.keys() ) {

        GetNavAreasInRadius( player.GetOrigin(), MaxSpawnDistance, raw_areas )

        foreach( area in raw_areas.values() ) {

            if ( area in ZNav.SafeNavAreas )
                areas[area] <- player
        }

        if ( !( i % 2 ) )
            yield true
    }

    local i = 0
    foreach( area, player in areas ) {

        if ( !( i % VALID_SPAWN_COLLECTION_PER_THINK ) )
            yield true

        i++

        if ( !player.IsValid() || !player.IsAlive() )
            continue

        else if ( !area.IsValidForWanderingPopulation() )
            continue

        else if ( area.GetDistanceSquaredToPoint( player.GetOrigin() ) < MinSpawnDistance * MinSpawnDistance )
            continue

        else if ( area.IsCompletelyVisibleToTeam( TF_TEAM_RED ) || area.IsCompletelyVisibleToTeam( TF_TEAM_BLUE ) )
            continue

        ValidSpawnPoints[area.GetCenter()] <- area
    }

    ZUtil.DevPrint( "Got %d valid spawn points", ValidSpawnPoints.len() )

    // delay the next collection to give zombies time to spawn
    EntFire( "__zspawner", "RunScriptCode", "CollectingSpawnPoints = false", VALID_SPAWN_COLLECTION_DELAY )
}

local gen = ZSpawner.GetValidSpawnPoints()

function ZSpawner::ThinkTable::ValidSpawnPointsThink() {

    if ( Paused || CurZombies >= MaxZombies )
        return -1

    if ( gen.getstatus() == "dead" )
        gen = ZSpawner.GetValidSpawnPoints()

    resume gen
    return -1
}

function ZSpawner::ThinkTable::SpawnZombiesThink() {

    if ( Paused || CurZombies >= MaxZombies )
        return -1

    else if ( !ValidSpawnPoints.len() || "PopulateSafeNav" in ZNav.ThinkTable )
        return -1

    local points = ValidSpawnPoints.keys()

    local spawn_point = points[RandomInt( 0, points.len() - 1 )]

    local zombie = BasicZombie( spawn_point )

    ZUtil.DevPrint( "Spawned %s at %s", zombie.base_ent.GetName(), spawn_point.ToKVString() )

    CurZombies++

    // AddOutput( zombie.base_ent, "OnKilled", "__zspawner", "RunScriptCode", "CurZombies--", -1, -1 )
    return -1
}

HOOK_EVENT( "teamplay_round_start", "ZSpawnerReset", function( _ ) {

    ZSpawner.CurZombies = 0
} )