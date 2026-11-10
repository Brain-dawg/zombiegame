// nav utils for generating navmesh on complex multi-stage maps
// also collecting "safe" nav areas ( areas that aren't too small, in death pits, or around the edges of the map )

__CREATE_SCOPE( "__znav", "ZNav", null, "ZNavThink" )

ZNav.AllNavAreas    <- {}
ZNav.SafeNavAreas   <- {}
ZNav.NAV_DEBUG      <- false // draw nav areas
ZNav.WALKABLE_ENTS  <- [ "info_player_teamspawn", "item_teamflag", "team_control_point", "trigger_capture_area", "func_capturezone" ]
ZNav.MAX_AREAS_PER_TICK <- 150

GetAllAreas( ZNav.AllNavAreas )

// we don't support maps with no nav for now
if ( !ZNav.AllNavAreas.len() && IsDedicatedServer() ) {

	local msg = "NO NAVMESH FOUND FOR" + MAPNAME + "! SWITCHING TO NEXT MAP\n"

	// local fmt = format( "\n%s%s%s\n", msg, msg, msg )

	ClientPrint( null, 3, "\x07FF0000" + msg )
	ClientPrint( null, 3, "\x07FF0000" + msg )
	ClientPrint( null, 3, "\x07FF0000" + msg )

	EntFire( "__zevents", "Kill" )
	EntFire( "player", "TerminateScriptScope" )
	EntFire( "__zutil", "CallScriptFunction", "ChangeLevel", 3 )

	Assert( false, msg.slice( 0, -1 ) )
}

function ZNav::GetWalkableEntities() {
    
    local walkable_ents = []

	local e
	foreach( ent in WALKABLE_ENTS )
		while ( e = FindByClassname( e, ent ) )
			walkable_ents.append( e )

	// PAYLOAD TRACKS BELOW

    // helper to recursively run through branching tracks
    local function _altpath( first, altpath, altname ) {

        if ( altpath ) {

            walkable_ents.append( altpath )

            if ( altpath = GetPropEntity( altpath, "m_paltpath" ) )
                walkable_ents.append( altpath )                    

            while ( altpath = GetPropEntity( altpath, "m_pnext" ) ) {

                if ( altpath == first )
                    continue

                walkable_ents.append( altpath )
            }
        }

        if ( altname != "" )
            while ( altpath = FindByName( altpath, altname ) )
                walkable_ents.append( altpath )
    }

    // grab the tracks from the watcher
    for ( local watcher; watcher = FindByClassname( watcher, "team_train_watcher" ); ) {

        local first, last, prev, altpath, altname
        local first_name = GetPropString( watcher, "m_iszStartNode" )
        local last_name = GetPropString( watcher, "m_iszGoalNode" )
        // grab the start and end tracks
        while ( last  = FindByName( last,  last_name  ) ) break
        while ( first = FindByName( first, first_name ) ) break

        if ( !( first && last ) )
        	ZUtil.DevPrint( "Error getting payload tracks:\n\n%s\nStart: %s\nEnd: %s\n\nYour path_tracks might be misconfigured?", watcher.GetName(), first_name, last_name )

        prev    = GetPropEntity( last, "m_pprevious" )
        altpath = GetPropEntity( prev, "m_paltpath" )
        altname = GetPropString( prev, "m_altName" )

        foreach ( path in [ altpath, first, last, prev ] ) {

            if ( !path || !path.IsValid() )
                continue

            altpath = GetPropEntity( path, "m_paltpath" )
            altname = GetPropString( path, "m_altName" )
            _altpath( first, altpath, altname )
        }

        if ( prev )
			walkable_ents.append( prev )

        // iterate backwards to the starting node
        while ( prev = GetPropEntity( prev, "m_pprevious" ) ) {

            walkable_ents.append( prev )
            altpath = GetPropEntity( prev, "m_paltpath" )
            altname = GetPropString( prev, "m_altName" )
            _altpath( first, altpath, altname )
        }
    }
    return walkable_ents
}

// pre-collect safe nav areas on load
function ZNav::GetSafeNavAreas() {

	if ( !AllNavAreas.len() )
		return

	ZUtil.ScriptEntFireSafe( self, "print( `\\n\\n Collecting nav areas, performance warnings will go away shortly...\\n\\n` )", 0.1 )

	local i = 0
	local color_valid  = [   0, 180,  20, 50  ]
	local color_small  = [   0,  20, 180, 50  ]
	local color_edge   = [   0, 180, 180, 50  ]
	local color_warn   = [ 180, 180,  20,  50 ]
	local color_danger = [ 180,   0,  20,  50 ]

	local color = color_valid
	local trace = {}

	// filter out areas that are too small or inside a trigger_hurt
	foreach( name, area in AllNavAreas ) {

		color = color_valid

		if ( area.GetSizeX() < 50 )
			color = color_small

		else if ( area.GetSizeY() < 50 )
			color = color_small

		else if ( ZUtil.IsPointInTrigger( area.GetCenter(), "trigger_hurt" ) )
			color = color_danger

		else {

			// this is too broken atm
			// for ( local i = 0; i < NUM_DIRECTIONS; i++ )
			// 	if ( !area.GetAdjacentArea( i, 1 ) ) {

			// 		color = color_edge
			// 		break
			// 	}

			if ( color != color_edge ) {

				// box trace straight up and see if there's a trigger_hurt above us
				trace.clear()
				trace.start <- area.GetCenter()
				trace.end 	<- area.GetCenter() + Vector( 0, 0, INT_MAX )
				trace.mask  <- CONTENTS_SOLID
				trace.hullmin <- area.GetCorner( NORTH_WEST )
				trace.hullmax <- area.GetCorner( SOUTH_EAST )

				TraceHull( trace )

				if ( trace.hit && trace.enthit && trace.enthit.GetClassname() == "trigger_hurt" )
					color = color_warn

			}
		}

		if ( color == color_valid )
			SafeNavAreas[area] <- name

		if ( NAV_DEBUG && color == color_edge )
			area.DebugDrawFilled( color[0], color[1], color[2], color[3], 8.0, true, 0.0 )

		i++

		if ( !( i % MAX_AREAS_PER_TICK ) ) // process this many nav areas per tick
			yield SafeNavAreas.len()
	}

	print( "\n\nSafe nav areas collected\n\n" )
}

local gen = ZNav.GetSafeNavAreas()
// resume gen // do one step right away before thinking

function ZNav::ThinkTable::PopulateSafeNav() {

	if ( gen.getstatus() == "dead" ) {

		delete ThinkTable.PopulateSafeNav
		return 1
	}
	local result = resume gen || SafeNavAreas.len()
	printf( "Safe Areas: %s / %s\n", result.tostring(), AllNavAreas.len().tostring() )
}

function ZNav::GetRandomSafeArea() { return SafeNavAreas.keys()[RandomInt( 0, SafeNavAreas.len() - 1 )] }

// NAV GENERATION TOOLS BELOW
function ZNav::NavGenerator() {

	local player = GetListenServerHost()

	local walkable_ents = GetWalkableEntities()

	local points_len = walkable_ents.len()

	printl( "WALKABLE POINTS: " + points_len )

	local generate_delay = 0.0
	// Process spawn points for current arena
	foreach( i, ent in walkable_ents ) {

		if ( !ent ) continue

		generate_delay += 0.01
		ZUtil.ScriptEntFireSafe( player, format( @"

			local origin = activator.GetAbsOrigin()
			self.SetAbsOrigin( origin )
			self.SnapEyeAngles( QAngle( 90, 0, 0 ) )
			SendToConsole( `nav_mark_walkable` )
			local progress = ( %d + 1 )
			local str = `Marking Spawn Point: ` + origin.ToKVString() + ` Progress: ` + progress + ` / ` + %d
			printl( str )
			ClientPrint( null, 3, str )

		", i, points_len ), generate_delay, ent )

		yield true
	}

	// Schedule nav generation
	ZUtil.ScriptEntFireSafe( ZUtil.Worldspawn, @"

		ClientPrint( null, 3, `Areas marked!` )
		ClientPrint( null, 3, `Generating nav...` )
		SendToConsole( `nav_generate` )

	", generate_delay + 0.5 )

	yield true


	AddThinkToEnt( player, null )
}

function ZNav::CreateNav() {

	if ( FileToString( "__NAV_DISCONNECT" ) == "1" )
		return DisconnectAreas(), StringToFile( "__NAV_DISCONNECT", "0" )

	EntFire( "team_round_timer", "Pause" )
	SendToConsole( "host_thread_mode 0; developer 1" )

	local player = GetListenServerHost()

	player.SetMoveType( MOVETYPE_NOCLIP, MOVECOLLIDE_DEFAULT )

	local scope = ZUtil.GetEntScope( player )

	local gen = NavGenerator()

	function NavThink() {

		if ( gen.getstatus() != "dead" )
			resume gen

		else if ( GetInt( "host_thread_mode" ) ) {

			StringToFile( "__NAV_DISCONNECT", "1" )
			// EntFire( "__znav", "CallScriptFunction", "DisconnectAreas", 1 )
			// ZUtil.ScriptEntFireSafe( player, "SendToConsole( `nav_analyze` )", 2 )
		}

		return 0.05
	}
	scope.NavThink <- NavThink
	AddThinkToEnt( player, "NavThink" )
}

// nav area disconnect: Modified from scripts by Mikusch & ficool2

function CTFNavArea::ComputePortal( to, dir ) {

	local center = Vector()
	local nwCorner = GetCorner( NORTH_WEST )
	local seCorner = GetCorner( SOUTH_EAST )
	local to_nwCorner = to.GetCorner( NORTH_WEST )
	local to_seCorner = to.GetCorner( SOUTH_EAST )

	if ( dir == NORTH || dir == SOUTH ) { 

		if ( dir == NORTH )
			center.y = nwCorner.y
		else
			center.y = seCorner.y

		local left = ( nwCorner.x > to_nwCorner.x ) ? nwCorner.x : to_nwCorner.x
		local right = ( seCorner.x < to_seCorner.x ) ? seCorner.x : to_seCorner.x

		if ( left < nwCorner.x )
			left = nwCorner.x
		else if ( left > seCorner.x )
			left = seCorner.x

		if ( right < nwCorner.x )
			right = nwCorner.x
		else if ( right > seCorner.x )
			right = seCorner.x

		center.x = ( left + right ) * 0.5
	}
	else { 

		if ( dir == WEST )
			center.x = nwCorner.x
		else
			center.x = seCorner.x

		local top = ( nwCorner.y > to_nwCorner.y ) ? nwCorner.y : to_nwCorner.y
		local bottom = ( seCorner.y < to_seCorner.y ) ? seCorner.y : to_seCorner.y

		if ( top < nwCorner.y )
			top = nwCorner.y
		else if ( top > seCorner.y )
			top = seCorner.y

		if ( bottom < nwCorner.y )
			bottom = nwCorner.y
		else if ( bottom > seCorner.y )
			bottom = seCorner.y

		center.y = ( top + bottom ) * 0.5
	}

	center.z = GetZ( center )
	return center
}

function CTFNavArea::GetClosestPointOnArea( pos ) {

	local close = Vector()
	local nwCorner = GetCorner( NORTH_WEST )
	local seCorner = GetCorner( SOUTH_EAST )
	close.x = ( pos.x - nwCorner.x >= 0 ) ? pos.x : nwCorner.x
	close.x = ( close.x - seCorner.x >= 0 ) ? seCorner.x : close.x
	close.y = ( pos.y - nwCorner.y >= 0 ) ? pos.y : nwCorner.y
	close.y = ( close.y - seCorner.y >= 0 ) ? seCorner.y : close.y
	close.z = GetZ( close )
	return close
}

function ZNav::DisconnectAreas() {

	GetAllAreas( AllNavAreas )

	function DisconnectAreaGenerator() {

		foreach ( i, area in AllNavAreas ) {

			// local center = area.GetCenter()
			for ( local dir = 0; dir < NUM_DIRECTIONS; dir++ ) {

				local adjacentAreas = {}
				area.GetAdjacentAreas( dir, adjacentAreas )

				foreach ( j, adjacentArea in adjacentAreas ) {

					local pos = area.ComputePortal( adjacentArea, dir )
					local from = pos + Vector()
					local to = pos + Vector()
					from.z = area.GetZ( from )
					to.z = adjacentArea.GetZ( to )

					to = adjacentArea.GetClosestPointOnArea( to )

					if ( ( to.z - from.z ) > STEP_HEIGHT ) { 

						area.DebugDrawFilled( 0, 255, 0, 32, 15, true, 0 )
						adjacentArea.DebugDrawFilled( 255, 0, 0, 32, 15, true, 0 )
						DebugDrawLine( from, to, 255, 255, 255, true, 15 )

						area.Disconnect( adjacentArea )
						printf( "Disconnected area #%d from area #%d\n", area.GetID(), adjacentArea.GetID() )
					}
				}
			}

			if ( !( i % MAX_AREAS_PER_TICK ) )
				yield true
		}
	}

	local gen = DisconnectAreaGenerator()
	function ThinkTable::DisconnectAreaThink() {

		if ( gen.getstatus() == "dead" )
			return SendToConsole( "nav_save" ), delete ThinkTable.DisconnectAreaThink

		resume gen
		return 0.05
	}
}