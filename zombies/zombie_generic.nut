class PathPoint {

	constructor( area, pos, how ) {

		this.area = area
		this.pos  = pos
		this.how  = how
	}

	area = null
	pos  = null
	how  = null
}

class BasicZombie {

	MAX_THREAT_DISTANCE = 256*256
	MIN_THREAT_DISTANCE = 96*96
	MAX_RECOMPUTE_TIME  = 5.0

    name            = "Zombie"
    description     = "A basic zombie"
    model           = "models/player/heavy.mdl"
    health          = 100
    speed           = 300
    damage          = 5
    attack_cooldown = 0.8
    scale           = 1.0
    sound_data      = null
    base_ent        = null

	attacking       = null
	next_attack_time	= null

	scope 				= null
	team  				= null
	time  				= null

	seq_idle = null					// Animation to use when idle
	seq_run = null					// Animation to use when running
	pose_move_x = null				// Pose parameter to set for running animation
	seq_attack = null				// Animation to use when attacking

	locomotion 			= null

	cur_pos     		= null
	cur_vel     		= null
	cur_speed   		= null
	cur_eye_pos 		= null
	cur_eye_ang 		= null
	cur_eye_fwd 		= null
	cur_weapon  		= null
	cur_ammo    		= null
	cur_melee   		= null

	damage_force 		= null

	wandering 			= null
	spawn_pos			= null
	squad_leader 				= null

	threat              = null
	threat_dist         = null
	threat_time         = null
	threat_lost_time    = null
	threat_aim_time     = null
	threat_behind_time  = null
	threat_visible      = null
	threat_pos          = null

	path_points		    = null
	skip_corners		= null
	path_index			= null
	path_count			= null
	path_areas			= null
	path_goalpoint      = null
	path_recompute_time	= null

	aim_time        	= null
	random_aim_pos  	= null
	random_aim_time 	= null
	stucktime			= null

	path_debug 			= null
	trace_debug 			= null
    constructor(pos = null) {

        this.sound_data = {
        
            attack    = "zombie/attack.wav"
            death     = "zombie/death.wav"
            idle      = "zombie/idle.wav"
            walk      = "zombie/walk.wav"
            run       = "zombie/run.wav"
            pain      = "zombie/pain.wav"
        }

		foreach(sound in this.sound_data)
			if ( !IsSoundPrecached( sound ) )
				PrecacheSound( sound )

        this.base_ent = BaseZombieEntity( pos )
		this.spawn_pos = pos
    
        this.scope       = base_ent.GetScriptScope()
		this.team        = base_ent.GetTeam()
		this.cur_pos     = base_ent.GetOrigin()
		this.cur_vel     = base_ent.GetAbsVelocity()
		this.cur_speed   = Vector()
		this.cur_eye_ang = base_ent.EyeAngles()
		this.cur_eye_pos = base_ent.EyePosition()
		this.cur_eye_fwd = base_ent.EyeAngles().Forward()
		this.locomotion  = base_ent.GetLocomotionInterface()

		this.damage_force = Vector()

		this.time = Time()

		this.health 			 = health
		this.threat 			 = null
        this.threat_dist         = 0.0
		this.threat_time         = 0.0
		this.threat_lost_time    = 0.0
		this.threat_aim_time     = 0.0
		this.threat_behind_time  = 0.0
		this.threat_visible      = false
		this.next_attack_time    = 0.0
		this.aim_time            = FLT_MAX
		this.random_aim_time     = 0.0
		this.attacking           = false
		this.path_points 		 = []
		this.path_index 		 = null
		this.path_count 		 = 0
		this.path_areas 		 = {}
		this.skip_corners		 = true
		this.path_goalpoint 	 = Vector()
		this.path_recompute_time = 0.0
		this.stucktime			 = 0.0
		this.path_debug			 = true
		this.trace_debug		 = false
		this.wandering 		 	 = false
		this.spawn_pos		 	 = Vector()
		this.squad_leader 		 = null
		
		this.seq_idle = base_ent.LookupSequence("Stand_MELEE_ALLCLASS")
		this.seq_run = base_ent.LookupSequence("Run_MELEE_ALLCLASS")
		// this.seq_attack = base_ent.LookupSequence("attackStand_MELEE_ALLCLASS")
		this.seq_attack = base_ent.LookupSequence("Stand_MELEE_ALLCLASS")
		this.pose_move_x = base_ent.LookupPoseParameter("move_x")

    }
    	function IsLookingTowards( target, cos_tolerance ) {

		local to_target = target - cur_eye_pos
		to_target.Norm()
		local dot = cur_eye_fwd.Dot( to_target )
		return ( dot >= cos_tolerance )
	}

	function IsInFieldOfView( target ) {

		local tolerance = 0.5736 // cos( 110/2 )

		if (!target || !target.IsValid())
			return false

		local delta = target.GetOrigin() - cur_eye_pos
		delta.Norm()
		if ( cur_eye_fwd.Dot( target ) >= tolerance )
			return true

		delta = target.GetCenter() - cur_eye_pos
		delta.Norm()
		if ( cur_eye_fwd.Dot( delta ) >= tolerance )
			return true

		delta = target.EyePosition() - cur_eye_pos
		delta.Norm()
		return ( cur_eye_fwd.Dot( delta ) >= tolerance )
	}

	function IsVisible( target ) {

		local trace = {
			start  = cur_eye_pos
			end    = target.EyePosition()
			mask   = MASK_OPAQUE
			ignore = base_ent
		}
		TraceLineEx( trace )

		if ( trace_debug )
			DebugDrawLine( trace.start, trace.end, 0, 255, 0, false, 1.0 )

		// printl( trace.ent )
		return !trace.hit
	}

	function IsValidThreat( target ) {

		return (
			target 
			&& target.IsValid() 
			&& target.IsAlive() 
			&& target.GetTeam() != base_ent.GetTeam() 
			&& target.GetLastKnownArea() 
			&& target.GetLastKnownArea().IsValidForWanderingPopulation() 
		)
	}

	function IsThreatVisible( target ) 		{ return threat_visible = ( IsInFieldOfView( target ) && IsVisible( target ) ), threat_visible }

	function GetThreatDistance( target ) 	{ return ( ( target.GetOrigin() || Vector() ) - cur_pos ).Length() }

    function GetThreatDistance2D( target ) 	{ return ( ( target.GetOrigin() || Vector() ) - cur_pos ).Length2D() }

	function GetThreatDistanceSqr( target ) { return ( ( target.GetOrigin() || Vector() ) - cur_pos ).LengthSqr() }

	function IsCurThreatVisible() 			{ return threat_visible = ( IsInFieldOfView( threat ) && IsVisible( threat ) ), threat_visible }

	function GetCurThreatDistance() 		{ return ( ( threat_pos || Vector() ) - ( cur_pos || Vector() ) ).Length() }

	function GetCurThreatDistanceSqr() 		{ return ( ( threat_pos || Vector() ) - ( cur_pos || Vector() ) ).LengthSqr() }

	function GetCurThreatDistanceSqr2D() 	{ return ( ( threat_pos || Vector() ) - ( cur_pos || Vector() ) ).Length2DSqr() }

	function FindClosestThreat( min_dist, must_be_visible = true ) {

		local closest_threat = null
		local closest_threat_dist = min_dist

		foreach ( player, _ in ZUtil.PlayerTables.All ) {

			if ( !player || !player.IsValid() )
				continue

			else if ( !IsValidThreat( player ) || ( must_be_visible && !IsThreatVisible( player ) ) )
				continue

			local dist = GetThreatDistanceSqr( player )

			if ( dist < closest_threat_dist ) {

				closest_threat = player
				closest_threat_dist = dist
			}
		}
		if ( closest_threat && path_debug )
			DebugDrawLine( base_ent.GetOrigin(), closest_threat.GetOrigin(), 255, 0, 0, false, 5.0 )

		return closest_threat
	}

	function CollectThreats( maxdist = INT_MAX, disguised = false, invisible = false, alive = true ) {

		local threatarray = []

		for ( local obj; obj = FindByClassname( obj, "obj_*" ); )
			if (obj.GetTeam() != base_ent.GetTeam())
				threatarray.append( obj )

		foreach ( player, _ in ZUtil.PlayerTables.Survivors ) {

			if ( !IsValidThreat( player ) || GetThreatDistanceSqr( player ) > maxdist )
				continue

			threatarray.append( player )
		}
		return threatarray
	}

	function SetThreat( target, visible = true ) {

		if ( !IsValidThreat( target ) || ( wandering && threat_time > time ) )
			return threat = null

		threat 			   = target
		threat_pos 		   = ( threat || ZUtil.Worldspawn ).GetOrigin()
		threat_visible 	   = visible
		threat_time 	   = time
		threat_behind_time = time + 0.5

		path_recompute_time = time + (MAX_RECOMPUTE_TIME * 0.5)

		wandering 		   = false
	}

	function LookAt( target_pos, min_rate, max_rate ) {

		local dt  = FrameTime()
		local dir = target_pos - cur_eye_pos
		dir.Norm()
		local dot = cur_eye_fwd.Dot( dir )

		local desired_angles = ZUtil.VectorAngles( dir )

		local rate_x = ZUtil.RemapValClamped( fabs( ZUtil.NormalizeAngle( cur_eye_ang.x ) - ZUtil.NormalizeAngle( desired_angles.x ) ), 0.0, 180.0, min_rate, max_rate )
		local rate_y = ZUtil.RemapValClamped( fabs( ZUtil.NormalizeAngle( cur_eye_ang.y ) - ZUtil.NormalizeAngle( desired_angles.y ) ), 0.0, 180.0, min_rate, max_rate )

		if ( dot > 0.7 ) {
			local t = ZUtil.RemapValClamped( dot, 0.7, 1.0, 1.0, 0.05 )
			local d = sin( 1.57 * t ) // pi/2
			rate_x *= d
			rate_y *= d
		}

		cur_eye_ang.x = ZUtil.NormalizeAngle( ZUtil.ApproachAngle( desired_angles.x, cur_eye_ang.x, rate_x * dt ) )
		cur_eye_ang.y = ZUtil.NormalizeAngle( ZUtil.ApproachAngle( desired_angles.y, cur_eye_ang.y, rate_y * dt ) )

		base_ent.SetAbsAngles( cur_eye_ang )
	}

	function OnTakeDamage( attacker ) {

		if ( health <= 0 ) {
			
			base_ent.EmitSound( sound_data.death )
			SetPropInt( base_ent, "m_lifeState", LIFE_DYING )
			base_ent.BecomeRagdollOnClient( damage_force )
			AddThinkToEnt( base_ent, null )
			base_ent.TerminateScriptScope()
			ZSpawner.CurZombies--
			return
		}

		else if ( (threat_time =- 1.0) > threat_time )
			return

		else if ( attacker != base_ent && threat_dist > GetThreatDistanceSqr( attacker ) )
			SetThreat( attacker )
	}

	function OnUpdate() {

		time = Time()

		cur_pos     = base_ent.GetOrigin()
		cur_vel     = base_ent.GetAbsVelocity()
		cur_speed   = cur_vel.LengthSqr()
		cur_eye_pos = base_ent.EyePosition()
		cur_eye_ang = base_ent.EyeAngles()
		cur_eye_fwd = cur_eye_ang.Forward()
		
		if ( !attacking ) {

			base_ent.SetSequence( cur_speed > 25.0 ? seq_run : seq_idle )
		}

		base_ent.SetPoseParameter( pose_move_x, cur_speed > 25.0 ? 1.0 : 0.0 )

		if ( base_ent.GetCycle() > 0.99 )
			base_ent.SetCycle( 0.0 )

		base_ent.StudioFrameAdvance()
		base_ent.DispatchAnimEvents( base_ent )
		
		if ( wandering && threat_time <= time )
			wandering = false

        if ( !IsValidThreat( threat ) ) {

			attacking = false


			local threats = CollectThreats( INT_MAX, true, true )

			if ( !threats.len() )
				return Wander( 6.0 )

			SetThreat( threats[RandomInt( 0, threats.len() - 1 )] )

			return
        }

		threat_pos = threat.GetOrigin()
		threat_dist = GetThreatDistanceSqr( path_goalpoint )

		// unstuck behavior, tell the base_ent to path to another nearby area
		stucktime = locomotion.GetStuckDuration()
	
		if ( stucktime < 1.0 ) {

			FindPathToThreat()
			MoveToThreat()
		}

		else if ( stucktime > 1.0 ) {

			path_recompute_time = time + 10.0
			local area = base_ent.GetLastKnownArea()
			
			if ( !area ) {

				GetNavAreasInRadius( cur_pos, 192.0, path_areas )

				// no nearby nav, just kill and respawn
				if ( !path_areas.len() )
					return ZUtil.KillZombie( base_ent )

				area = path_areas.values()[ RandomInt( 0, path_areas.len() - 1 ) ]
			}
			// no nearby nav, just kill and respawn
			if ( !area )
				return ZUtil.KillZombie( base_ent )

			else {

				// if ( path_debug ) {

				// 	printf( "base_ent %s STUCK!\n pos: %s stuck time: %.2f last known area: '%s'\n", base_ent.tostring(), cur_pos.ToKVString(), stucktime, ""+area )
				// 	SetPropBool( base_ent, "m_bGlowEnabled", stucktime > 5.0 )
				// }
		
				for ( local navdir = 0, new_pos, new_area; navdir < NUM_DIRECTIONS; navdir++ ) {

					new_area = area.GetRandomAdjacentArea( navdir )

					if ( !new_area || !(new_area in ZNav.SafeNavAreas) )
						continue

					new_pos = new_area.FindRandomSpot()

					// 256 hu^2
					if ( ( new_pos - cur_pos ).LengthSqr() <= 65535.0 ) {

						if ( path_debug ) {

							DebugDrawText( new_pos, "zombie " + base_ent.tostring() + " moved to '" + new_pos.ToKVString() + "'", false, 1.0 )
							new_area.DebugDrawFilled( 255, 0, 255, 80, 5.0, true, 0.0 )
						}

						ResetPath()
						UpdatePath( new_pos, true )

						// very stuck, probably in world geometry/map entity
						if ( stucktime > 10.0 || 
							( !IsVisible( threat ) 
							&& threat_dist > MAX_THREAT_DISTANCE 
							&& !new_area.IsCompletelyVisibleToTeam( TF_TEAM_RED ) 
							&& !new_area.IsCompletelyVisibleToTeam( TF_TEAM_BLUE ) ) 
						) {

							base_ent.SetAbsOrigin( new_pos + Vector( 0, 0, 20 ) )
							locomotion.ClearStuckStatus( "Moved to new nav area" )
							stucktime = 0.0
							SetThreat( null )
						}

						break
					}

					if ( path_debug )
						new_area.DebugDrawFilled( 255, 255, 0, 50, 0.02, true, 0.0 )
				}
			}
		}

		return -1
	}

	function FindPathToThreat() {

		if ( path_recompute_time > time )
			return

		if ( ( !path_count ) || threat_dist > MAX_THREAT_DISTANCE ) {

			local area = GetNavArea( threat_pos, 0.0 )
			if ( area )
				UpdatePath( threat_pos, true )
		}
	}

	function ResetPath() {

		path_areas.clear()
		path_points.clear()
		path_index = null
		path_count = 0
		path_recompute_time = 0
	}

	function UpdatePath( target_pos, no_corners = false, move = false, lookat = false ) {

		local dist_to_target = ( target_pos - base_ent.GetOrigin() ).LengthSqr()
        path_count = path_points.len() - 1
		path_goalpoint = target_pos
		ZUtil.DevPrint( "Updating path to %s", path_goalpoint.ToKVString() )

		if ( path_recompute_time < time ) {

			ResetPath()

			local pos_start = base_ent.GetOrigin()
			local pos_end   = target_pos

			local area_start = GetNavArea( pos_start, 128.0 )
			local area_end   = GetNavArea( pos_end, 128.0 )

			if ( !area_start )
				area_start = GetNearestNavArea( pos_start, 128.0, false, true )
			if ( !area_end )
				area_end   = GetNearestNavArea( pos_end, 128.0, false, true )

			if ( !area_start || !area_end ) {

				ZUtil.DevPrint( "Invalid start/end areas: %s, %s", ""+area_start, ""+area_end )
				// if ( !wandering )
				Wander( 6.0 )
				return
			}

			else if ( !GetNavAreasFromBuildPath( area_start, area_end, pos_end, 0.0, TF_TEAM_HALLOWEEN, true, path_areas ) ) {
				
				// hack to make zombies move straight to the threat if we can't find a proper path
				// if ( IsVisible( threat ) )
					// return SetPropInt( base_ent, "m_nWaterLevel", 3 )

				ZUtil.DevPrint( "No path found from %s to %s", ""+area_start, ""+area_end )

				// if ( !wandering )
				Wander( 6.0 )
				return
			}

			else {

				// Construct path_points
				local area_count = path_areas.len()
				path_areas["area"+area_count] <- area_start
				local area = path_areas["area0"]

				// Initial run grabbing area center
				for ( local i = 1; i < area_count; i++ ) {

					path_points.append( PathPoint( area, area.FindRandomSpot(), area.GetParentHow() ) )
					area = area.GetParent()
				}

				path_points.reverse()
				path_points.append( PathPoint( area_end, area_end.FindRandomSpot(), NUM_TRAVERSE_TYPES ) )
				path_count = path_points.len() - 1
				path_index = path_count

				// Go through again and replace center with border point of next area

				local to_c1, to_c2, fr_c1, fr_c2
				for ( local i = 0; i <= path_count; i++ ) {

					if ( !( i in path_points) || !(i + 1 in path_points) )
						continue


					local path_from = path_points[i]
					local path_to = ( i < path_count ) ? path_points[i + 1] : null

					if ( path_to ) {

						local dir_to_from = path_to.area.ComputeDirection( path_from.pos )
						local dir_from_to = path_from.area.ComputeDirection( path_to.pos )

						to_c1 = path_to.area.GetCorner( dir_to_from )
						to_c2 = path_to.area.GetCorner( dir_to_from + 1 )
						fr_c1 = path_from.area.GetCorner( dir_from_to )
						fr_c2 = path_from.area.GetCorner( dir_from_to + 1 )

						local minarea = {}
						local maxarea = {}

						if ( ( to_c1 - to_c2 ).LengthSqr() < ( fr_c1 - fr_c2 ).LengthSqr() ) {

							minarea.area <- path_to.area
							maxarea.area <- path_from.area

							if ( !no_corners ) {

								minarea.c1 <- to_c1
								minarea.c2 <- to_c2

								maxarea.c1 <- fr_c1
								maxarea.c2 <- fr_c2
							}
						}
						else {

							minarea.area <- path_from.area
							maxarea.area <- path_to.area

							if ( !no_corners ) {

								minarea.c1 <- fr_c1
								minarea.c2 <- fr_c2

								maxarea.c1 <- to_c1
								maxarea.c2 <- to_c2
							}
						}

						// Get center of smaller area's edge between the two
						local vec = minarea.area.FindRandomSpot()

						// don't do any corner shortcuts and follow the strict path
						if ( !no_corners ) {

							if ( !dir_to_from || dir_to_from == 2 ) { // GO_NORTH, GO_SOUTH
								vec.y = minarea.c1.y
								vec.z = minarea.c1.z
							}
							else if ( dir_to_from == 1 || dir_to_from == 3 ) { // GO_EAST, GO_WEST
								vec.x = minarea.c1.x
								vec.z = minarea.c1.z
							}
						}
						path_from.pos = vec
					}
				}
			}

			// Base recompute off distance to target
			// Every 500hu away increase our recompute time by 0.1s
			local path_recompute_mod = 0.1 * ( dist_to_target / 250000 ) // 500^2 = 250000

			path_recompute_time = time + ( path_recompute_mod > MAX_RECOMPUTE_TIME ? MAX_RECOMPUTE_TIME : path_recompute_mod )
		}

		if ( path_index == null )
			path_index = path_count

		if ( !(path_index in path_points) || ( path_points[path_index].pos - base_ent.GetOrigin() ).LengthSqr() < 128.0 ) {
			return ResetPath()
		}

		if ( path_debug ) {

			for ( local i = 0; i <= path_count; i++ ) {
				if ( i in path_points && path_debug )
					DebugDrawLine( path_points[i].pos, path_points[ i+1 < path_count ? i+1 : i ].pos, 0, 0, 255, false, 0.1 )
				// else
					// __DumpScope( 0, path_points )
			}

			local area_count = path_areas.len()

			for ( local i = 0, _area = path_areas["area0"]; i < area_count; i++ ) {
				
				if ( !_area ) continue

				local x = ( ( area_count - i - 0.0 ) / area_count ) * 255.0
				_area.DebugDrawFilled( 0, x, 0, 50, 0.075, true, 0.0 )

				_area = _area.GetParent()
			}
		}

		if ( move )
			MoveToThreat( lookat )			
	}

	function TryAvoidObstacles( target_pos ) {

		// Get 2D forward motion vector
		local motion_fwd = target_pos - cur_pos
		motion_fwd.z = 0.0
		motion_fwd.Norm()
		
		// Get 2D lateral motion vector, which is perpendicular to the forward motion vector, going left or right
		local motion_lat = Vector(-motion_fwd.y, motion_fwd.x)

		// Get the ground normal and compute the 3D motion vectors
		local normal = locomotion.GetGroundNormal()
		motion_fwd = motion_lat.Cross(normal)
		motion_lat = motion_fwd.Cross(normal)

		// The length vector of the traces going forward
		local fwd_vec = motion_fwd * 60.0
		// The offset to the left/right from the original position
		local lat_vec = motion_lat * 60.0

		// trace left and right to avoid obstacles
		local trace_offset = Vector( cur_pos.x, cur_pos.y, cur_pos.z + locomotion.GetStepHeight() )
		local point_offset = target_pos

		local left_traces = TraceLinePlayersIncluded( trace_offset, trace_offset + fwd_vec + lat_vec, base_ent )
		// left_traces += TraceLine( trace_offset, trace_offset + fwd_vec + (lat_vec * 0.5), base_ent )
		left_traces += TraceLinePlayersIncluded( trace_offset, trace_offset + fwd_vec + (lat_vec * 0.25), base_ent )

		local right_traces = TraceLinePlayersIncluded( trace_offset, trace_offset + fwd_vec - lat_vec, base_ent )
		// right_traces += TraceLine( trace_offset, trace_offset + fwd_vec - (lat_vec * 0.5), base_ent )
		right_traces += TraceLinePlayersIncluded( trace_offset, trace_offset + fwd_vec - (lat_vec * 0.25), base_ent )

		if ( left_traces != 2.0 )
			point_offset -= lat_vec

		else if ( right_traces != 2.0 )
			point_offset += lat_vec

		if ( trace_debug && left_traces + right_traces != 4.0 ) {

			// for ( local i = left_traces + right_traces; i > 0; i-- ) {
			// 	DebugDrawLine( trace_offset, trace_offset + fwd_vec + (lat_vec * (i * 0.25)), 255, 0, 33 * (left_traces + right_traces), false, 0.1 )
			// }

			DebugDrawLine( trace_offset, trace_offset + fwd_vec + lat_vec, 255, 0, 200, false, 0.1 )
			// DebugDrawLine( trace_offset, trace_offset + fwd_vec + (lat_vec * 0.5), 255, 0, 200, false, 0.1 )
			DebugDrawLine( trace_offset, trace_offset + fwd_vec + (lat_vec * 0.25), 255, 0, 200, false, 0.1 )

			DebugDrawLine( trace_offset, trace_offset + fwd_vec - lat_vec, 255, 0, 200, false, 0.1 )
			// DebugDrawLine( trace_offset, trace_offset + fwd_vec - (lat_vec * 0.5), 255, 0, 200, false, 0.1 )
			DebugDrawLine( trace_offset, trace_offset + fwd_vec - (lat_vec * 0.25), 255, 0, 200, false, 0.1 )

			local box = Vector(10, 10, 10)
			DebugDrawBox( target_pos, box * -1.0, box, 255, 255, 0, 10, 0.1 )
			
			if ( point_offset != target_pos )
				DebugDrawBox( point_offset, box * -1.0, box, 0, 255, 255, 10, 0.1 )
		}

		return point_offset
	}

	function Wander( howlong = 0.0 ) {

		if ( wandering )
			return

		wandering = true

		ResetPath()

		threat_time = time + howlong
		
		local wander_pos = ZNav.GetRandomSafeArea().GetCenter()
		// if ( ( cur_pos - spawn_pos ).LengthSqr() < MAX_THREAT_DISTANCE )
			// wander_pos = ZNav.GetRandomSafeArea().GetCenter()

		ZUtil.DevPrint( "Wandering for %.2f seconds to %s", howlong, wander_pos.ToKVString() )

		SetThreat( null )
		UpdatePath( wander_pos, false )
		path_recompute_time = time + (MAX_RECOMPUTE_TIME * 2)
	}

	function MoveToThreat( lookat = true, turnrate_min = 600, turnrate_max = 1500 ) {

		// if ( !(path_index in path_points) )
		// 	__DumpScope( 0, path_points )

		// we're underwater or very close and can see our target, just move directly at them
		if ( ( base_ent.GetWaterLevel() >= 2 || threat_dist <= MAX_THREAT_DISTANCE ) && IsVisible( threat ) ) {

			AttackThreat()

			if ( threat_dist < MIN_THREAT_DISTANCE )
				return

			locomotion.FaceTowards( threat_pos )
			LookAt( threat_pos, turnrate_min, turnrate_max )
			locomotion.SetDesiredSpeed( speed )

			// printl( locomotion.FractionPotentialGap( cur_pos, threat_pos ) + " + " + locomotion.HasPotentialGap( cur_pos, threat_pos ) )

			// if ( !locomotion.IsClimbingOrJumping() && locomotion.HasPotentialGap( cur_pos, threat_pos ) )
				// locomotion.JumpAcrossGap( threat_pos, Vector() )

			locomotion.Approach( TryAvoidObstacles( threat_pos ), 1.0 )
			ResetPath()
			path_recompute_time = time + 1.0
			return
		}

		if ( path_index == null || !( path_index in path_points ) )
			return UpdatePath( threat_pos, true )

		local point = path_points[0].pos
		local area = path_points[0].area

		local frac = locomotion.FractionPotentiallyTraversable( cur_pos, point, true )

		if ( area.GetDistanceSquaredToPoint( cur_pos ) < 64.0 || area.ContainsOrigin(cur_pos) ) {

			if ( path_debug ) {

				path_points[0].area.DebugDrawFilled( 0, 0, 255, 255, 1.0, true, 0.0 )
				DebugDrawText( point, "AREA REACHED!", false, 1.0 )
			}

			path_points.remove( 0 )
			if ( path_index )
				path_index--
		}

		if ( frac < 0.05 ) {
			
			if ( path_debug ) {

				// printf( "UPDATING PATH! base_ent: %s frac: %.2f\n", base_ent.tostring(), frac )
				DebugDrawText( cur_pos, "UPDATING PATH! base_ent: " + base_ent.tostring() + " frac: " + frac.tostring(), false, 1.0 )
				DebugDrawLine( cur_pos, point, 255, 0, 100, false, 0.1 )

				if ( base_ent.GetLastKnownArea() )
					base_ent.GetLastKnownArea().DebugDrawFilled( 0, 0, 255, 255, 5.0, true, 0.0 )
			}

			return UpdatePath( threat_pos, true )
		}

		locomotion.FaceTowards( threat_pos )
		locomotion.SetDesiredSpeed( speed )
		locomotion.Approach( TryAvoidObstacles( point ), 1.0 )
		// locomotion.DriveTo( point )

		local look_pos = Vector( point.x, point.y, cur_eye_pos.z )

		if ( lookat )
			LookAt( look_pos, turnrate_min, turnrate_max )

		if ( path_debug ) {

			DebugDrawLine( cur_pos, point, 255, 0, 200, false, 0.1 )

			local area_count = path_areas.len()

			local i = 0
			foreach( area in path_areas ) {

				i++
				local x = ( ( area_count - i - 0.0 ) / area_count ) * 255.0
				area.DebugDrawFilled( x, (x / 2), 0, 50, 0.075, true, 0.0 )
			}
		}
	}

	function AttackThreat() {

		if ( threat_dist > MIN_THREAT_DISTANCE || !threat.IsAlive() || !IsVisible( threat ) )
			return attacking = false

		if ( next_attack_time > time )
			return

		attacking = true

		base_ent.SetSequence( seq_attack )
		base_ent.SetPoseParameter( pose_move_x, 0.15 )
		locomotion.SetDesiredSpeed( speed * 0.015 )

		threat.TakeDamage( damage, DMG_CLUB, base_ent )

		next_attack_time = time + attack_cooldown + base_ent.GetSequenceDuration( seq_attack )
	}
}

function BaseZombieEntity( pos = Vector() ) {

    local ent = CreateByClassname( "base_boss" )

	local baseclass = this

	ent.KeyValueFromVector( "origin", pos )
    ent.KeyValueFromFloat( "speed", speed )
    ent.KeyValueFromFloat( "health", INT_MAX )
    ent.KeyValueFromString( "model", model )
	ent.KeyValueFromInt("skin", 5 )
	ent.KeyValueFromFloat( "playbackrate", 1.0 )
	ent.KeyValueFromString( "targetname", "__z_" + name + "_" + ent.entindex() )
	ent.SetTeam( TF_TEAM_HALLOWEEN )

    SetPropInt( ent, "m_bloodColor", 2 )
	SetPropVector( ent, "m_vecViewOffset", Vector(0, 0, 56) )

    ent.DispatchSpawn()

	// makes zombies non-solid to eachother but still solid to players/world
	// this breaks flamethrowers, see flame_boss_damage.nut
	// melee weapons are slightly janky, we'll probably rework them anyway.
	ent.SetSolidFlags( FSOLID_CUSTOMBOXTEST )

	ent.AddEFlags( EFL_ZOMBIE )

	ent.AcceptInput( "SetStepHeight", ""+STEP_HEIGHT * 2, null, null )
	ent.AcceptInput( "SetMaxJumpHeight", "64", null, null )
	ent.ValidateScriptScope()
	ent.GetScriptScope().baseclass <- baseclass

	local function ZombieUpdate() { baseclass.OnUpdate() }

	ZUtil.AddThink( ent, ZombieUpdate )
    return ent
}

HOOK_EVENT("npc_hurt", "ZombieTakeDamage", function(params) {

	local victim   = EntIndexToHScript( params.entindex )
	local scope = victim.GetScriptScope()
	local attacker = params.attacker_player

	if ( !scope || !("baseclass" in scope) )
		return
	
	scope.baseclass.health -= params.damageamount

	scope.baseclass.OnTakeDamage( GetPlayerFromUserID( attacker ) )

})

HOOK_EVENT( "OnTakeDamage", "ZombieTakeDamage", function(params) {

	local victim = params.const_entity

	if ( victim.IsPlayer() && params.attacker && "baseclass" in params.attacker.GetScriptScope() && params.damage_type & DMG_CRUSH ) {

		params.early_out = true
		params.damage = 0.0
		return false
	}

	local scope = victim.GetScriptScope()

	if ( "baseclass" in scope )
		scope.baseclass.damage_force = params.damage_force
})