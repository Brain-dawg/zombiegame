function Include( file, scope = null, prefix = "zombiegame/" ) {

    if ( !scope )
        scope = ROOT
    IncludeScript( prefix + file, scope )
}

Include( "constants" )
Include( "itemdef_constants" )
Include( "create_scope" )
Include( "event_wrapper" )
Include( "util" )
Include( "navutils" )
Include( "flame_boss_damage" )
Include( "zombies/spawn_zombies" )