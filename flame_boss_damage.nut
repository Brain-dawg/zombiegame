// Recreates tf_flame_manager particle motion in VScript and applies flamethrower
// damage to base_boss entities. Players are still damaged by the real flame manager.

// all of this is one big hack to work around our other hack of setting base_boss solid flags to FSOLID_CUSTOMBOXTEST
// FSOLID_CUSTOMBOXTEST means zombies don't collide with eachother, but still collide with enemies
// the catch: flamethrowers use hull traces to deal damage, FSOLID_CUSTOMBOXTEST breaks hull traces
// it also makes melee slightly jank ( falls back to ray trace instead of hull trace for detecting hits )
// TODO: handle melee traces somewhere else

__CREATE_SCOPE( "__zflame_manager", "FlameManager", null, "FlameManagerThink" )

FlameManager.FLAME_DAMAGE 			<- 13.0
FlameManager.FLAME_BOX_SIZE 		<- 12.0
FlameManager.FLAME_POINT_COUNT 		<- 30
FlameManager.FLAME_ORIGIN_RIGHT 	<- 5.0
FlameManager.FLAME_BURN_INTERVAL 	<- 0.075
FlameManager.FLAME_ORIGIN_FORWARD 	<- 40.0
FlameManager.FLAME_DAMAGE_TIME_CAP  <- 0.5
FlameManager.FLAME_MIN_DAMAGE_SCALE <- 0.5

FlameManager.DEBUG_ENABLED 			<- false

// TraceHull cannot set COLLISION_GROUP_DEBRIS, so this brush mask is the stand-in.
FlameManager.FLAME_BRUSH_MASK <- CONTENTS_SOLID|CONTENTS_WINDOW|CONTENTS_GRATE|CONTENTS_MOVEABLE

// MASK_SOLID. A ray with CONTENTS_MONSTER hits a CUSTOMBOXTEST boss. A hull trace does not.
FlameManager.FLAME_HIT_MASK   <- CONTENTS_SOLID|CONTENTS_WINDOW|CONTENTS_GRATE|CONTENTS_MOVEABLE|CONTENTS_MONSTER

function FlameManager::FlameClamp( value, low, high ) { 

	if ( value < low )
		return low
	if ( value > high )
		return high
	return value
}

function FlameManager::FlameRemapClamped( value, a, b, c, d ) { 

	if ( a == b )
		return c
	local t = FlameClamp( (value - a ) / ( b - a ), 0.0, 1.0 )
	return c + ( d - c ) * t
}

function FlameManager::FlameDot( a, b ) { 

	return a.x * b.x + a.y * b.y + a.z * b.z
}

function FlameManager::FlameLength( v ) { 

	return sqrt( v.x * v.x + v.y * v.y + v.z * v.z )
}

function FlameManager::FlameNormalize( v ) {

	local len = FlameLength( v )
	if ( len < 0.000001 )
		return Vector()
	return Vector( v.x / len, v.y / len, v.z / len )
}

function FlameManager::FlameCross( a, b ) {

	return Vector(
		a.y * b.z - a.z * b.y,
		a.z * b.x - a.x * b.z,
		a.x * b.y - a.y * b.x )
}

// CUniformRandomStream. Seeded the same way InitializePoint seeds it.
FlameManager.FlameRandom <- class {

	idum = 0
	iy = 0
	iv = null

	constructor() { 

		iv = array( 32, 0 )
	}

	function SetSeed( seed ) { 

		if ( seed < 0 )
			idum = seed
		else
			idum = -seed
		iy = 0
	}

	function Generate() { 

		local IA = 16807
		local IM = 2147483647
		local IQ = 127773
		local IR = 2836
		local NTAB = 32
		local NDIV = 67108864

		if ( idum <= 0 || !iy ) { 

			if ( -idum < 1 )
				idum = 1
			else
				idum = -idum

			for ( local j = NTAB + 7; j >= 0; j-- ) { 

				local k = ( idum / IQ ).tointeger()
				idum = ( IA * ( idum - k * IQ ) - IR * k ).tointeger()
				if ( idum < 0 )
					idum += IM
				if ( j < NTAB )
					iv[j] = idum
			}
			iy = iv[0]
		}

		local k = ( idum / IQ ).tointeger()
		idum = ( IA * ( idum - k * IQ ) - IR * k ).tointeger()
		if ( idum < 0 )
			idum += IM

		local j = ( iy / NDIV ).tointeger()
		iy = iv[j]
		iv[j] = idum
		return iy
	}

	function RandomFloat( low, high ) { 

		local fl = ( 1.0 / 2147483647.0 ) * Generate()
		local rnmx = 1.0 - 1.2e-7
		if ( fl > rnmx )
			fl = rnmx
		return fl * ( high - low ) + low
	}
}

function FlameManager::FlameReadParams( manager ) { 

	return {
		speed 			= GetPropFloat( manager, "m_flFlameSpeed" )
		lifetime 		= GetPropFloat( manager, "m_flFlameLifeTime" )
		lifeOffset 		= GetPropFloat( manager, "m_flRandomLifeTimeOffset" )
		gravity 		= GetPropFloat( manager, "m_flFlameGravity" )
		drag 			= GetPropFloat( manager, "m_flFlameDrag" )
		up 				= GetPropFloat( manager, "m_flFlameUp" )
		spread 			= GetPropFloat( manager, "m_flSpreadDegree" )
		startSize 		= GetPropFloat( manager, "m_flFlameStartSizeMult" )
		endSize 		= GetPropFloat( manager, "m_flFlameEndSizeMult" )
		redirectedSize 	= GetPropFloat( manager, "m_flRedirectedFlameSizeMult" )
		ignorePlayerVelocity	= GetPropFloat( manager, "m_flFlameIgnorePlayerVelocity" )
		reflectLife 	= GetPropFloat( manager, "m_flFlameReflectionAdditionalLifeTime" )
		reflectDamage 	= GetPropFloat( manager, "m_flFlameReflectionDamageReduction" )
		maxReflect 		= GetPropInt( manager, "m_iMaxFlameReflectionCount" )
		shouldReflect 	= GetPropInt( manager, "m_nShouldReflect" )
		randomSeed 		= GetPropInt( manager, "m_nRandomSeed" )
	}
}

function FlameManager::FlameApplySpread( forward, spreadDeg, rng ) { 

	if ( spreadDeg <= 0.0 )
		return forward

	local spread = spreadDeg * 3.141592653589793 / 180.0
	local right
	local up
	if ( !forward.x && !forward.y ) { 

		right = Vector( 0, -1, 0 )
		up = Vector( -forward.z, 0, 0 )
	}
	else { 

		right = FlameNormalize( FlameCross( forward, Vector( 0, 0, 1 ) ) )
		up = FlameNormalize( FlameCross( right, forward ) )
	}

	// ai_shot_bias_min/max default to 1, and ApplySpread is called with bias 1.
	local flatness = 0.5
	local x
	local y
	local z
	do { 

		x = rng.RandomFloat( -1.0, 1.0 ) * flatness + rng.RandomFloat( -1.0, 1.0 ) * ( 1.0 - flatness )
		y = rng.RandomFloat( -1.0, 1.0 ) * flatness + rng.RandomFloat( -1.0, 1.0 ) * ( 1.0 - flatness )
		z = x * x + y * y
	} while ( z > 1.0 )

	return forward + right * ( x * spread ) + up * ( y * spread )
}

function FlameManager::FlameSpawnParticle( manager, slot, spawnTick, params ) { 

	local weapon = manager.GetOwner()
	local attacker
	if ( weapon )
		attacker = weapon.GetOwner()

	local forward = Vector( 1, 0, 0 )
	local right = Vector( 0, -1, 0 )
	local origin = manager.GetOrigin()
	local attackerVelocity = Vector( 0, 0, 0 )
	local scale = 1.0

	if ( attacker ) { 

		local eye = attacker.EyeAngles()
		forward = eye.Forward()
		right = eye.Left() * -1.0
		scale = GetPropFloat( attacker, "m_flModelScale" )
		origin = attacker.EyePosition() + forward * ( FLAME_ORIGIN_FORWARD * scale ) + right * ( FLAME_ORIGIN_RIGHT * scale )
		attackerVelocity = attacker.GetLocalVelocity()
	}

	// Same order as InitializePoint: spread consumes random numbers, then lifetime.
	local rng = FlameRandom()
	rng.SetSeed( spawnTick + params.randomSeed + slot )

	local direction = FlameApplySpread( forward, params.spread, rng )
	local lifetime = params.lifetime
	if ( params.lifeOffset )
		lifetime = lifetime + rng.RandomFloat( -params.lifeOffset, params.lifeOffset )

	return {
		position = origin
		prev = origin
		velocity = direction * params.speed
		attackerVelocity = attackerVelocity
		spawnTime = Time()
		lifetime = lifetime
		hitWall = 0
		dead = false
		spawnTick = spawnTick
		enthit = null
	}
}

function FlameManager::FlameRadius( particle, params ) { 

	local age = Time() - particle.spawnTime
	local radius = FLAME_BOX_SIZE * FlameRemapClamped( age, 0.0, particle.lifetime, params.startSize, params.endSize )
	if ( particle.hitWall > 0 )
		radius = radius * params.redirectedSize
	return radius
}

function FlameManager::FlameDragSpeed( speed, drag, dt ) { 

	return FlameClamp( speed - dt * drag * speed, 0.0, speed )
}

function FlameManager::FlameStepParticle( manager, particle, params, dt ) { 

	particle.enthit = null
	if ( particle.dead || dt <= 0.0 )
		return

	local gravity = Vector( 0, 0, params.gravity * dt )
	local dir = FlameNormalize( particle.velocity )
	local additional = Vector( 0, 0, params.up ) + dir * FlameDot( particle.attackerVelocity, dir )
	local stepVelocity = particle.velocity + gravity + additional
	local newPos = particle.position + stepVelocity * dt
	local radius = FlameRadius( particle, params )
	local hull = Vector( radius, radius, radius )

	local tr = {
		start = particle.position
		end = newPos
		hullmin = hull * -1.0
		hullmax = hull
		mask = FLAME_BRUSH_MASK
		ignore = manager
	}
	TraceHull( tr )

	if ( DEBUG_ENABLED ) {

		DebugDrawBox( tr.start, tr.hullmin, tr.hullmax, tr.fraction < 1.0 ? 255 : 0, 0, tr.fraction < 1.0 ? 0 : 255 , 100, 0.1 )
	}

	local stored = particle.velocity
	if ( "startsolid" in tr && tr.startsolid ) { 

		particle.dead = true
		return
	}

	if ( tr.fraction < 1.0 ) { 

		particle.hitWall++
		particle.lifetime += params.reflectLife
		particle.attackerVelocity = Vector()

		if ( params.maxReflect > 0 && particle.hitWall > params.maxReflect ) { 

			particle.dead = true
			return
		}

		local normal = tr.plane_normal
		local slide = stepVelocity - normal * FlameDot( stepVelocity, normal )
		stored = slide
		if ( params.shouldReflect > 0 )
			stored = slide * 2.0 - stepVelocity

		newPos = tr.pos + normal * radius + stored * ( (1.0 - tr.fraction ) * dt )
	}

	local speed = FlameLength( stored )
	if ( speed > 0.000001 ) { 

		local newSpeed = FlameDragSpeed( speed, params.drag, dt )
		particle.velocity = stored * ( newSpeed / speed ) + gravity
	}
	else { 

		particle.velocity = gravity
	}

	if ( params.ignorePlayerVelocity ) { 

		local attackerSpeed = FlameLength( particle.attackerVelocity )
		if ( attackerSpeed > 0.000001 ) { 

			local newSpeed = FlameDragSpeed( attackerSpeed, params.drag, dt )
			particle.attackerVelocity = particle.attackerVelocity * ( newSpeed / attackerSpeed )
		}
	}

	particle.prev = particle.position
	particle.position = newPos

	// The hull above is brush-only. A box trace against a CUSTOMBOXTEST boss returns no hit.
	// This ray uses the resolved step and can hit the boss bbox.
	local hit = {
		start = particle.prev
		end = particle.position
		mask = FLAME_HIT_MASK
		ignore = manager
	}
	TraceLineEx( hit )
	if ( "enthit" in hit )
		particle.enthit = hit.enthit
}

function FlameManager::FlameDamageBosses( manager, scope ) { 

	local weapon = manager.GetOwner()
	local attacker
	if ( weapon ) attacker = weapon.GetOwner()
	if ( !attacker ) return

	local now = Time()
	local dmgType = DMG_BURN

	if ( attacker.IsCritBoosted() )
		dmgType = dmgType | DMG_ACID

	foreach ( particle in scope.particles ) { 

		if ( !particle || particle.dead || !particle.enthit )
			continue

		local victim = particle.enthit
		if ( !victim.IsEFlagSet( EFL_ZOMBIE ) || !victim.IsAlive() || victim == attacker )
			continue

		local id = victim.entindex()
		if ( id in scope.lastBurn && ( now - scope.lastBurn[id] ) < FLAME_BURN_INTERVAL )
			continue

		local age = now - particle.spawnTime
		local scale = FlameRemapClamped( age, 0.0, particle.lifetime * FLAME_DAMAGE_TIME_CAP, 1.0, FLAME_MIN_DAMAGE_SCALE )
		for ( local i = 0; i < particle.hitWall; i++ )
			scale = scale * scope.params.reflectDamage

		local damage = scale * FLAME_DAMAGE
		if ( damage < 1.0 )
			damage = 1.0

		victim.TakeDamage( damage, dmgType, attacker )

		if ( DEBUG_ENABLED ) {
			local radius = FlameRadius( particle, scope.params )
			local box = Vector( radius, radius, radius )
			DebugDrawBox( particle.prev, box * -1.0, box, 255, 255, 0, 10, 0.1 )
		}

		if ( id in scope.lastBurn )
			scope.lastBurn[id] = now
		else
			scope.lastBurn[id] <- now
	}
}

// applied to tf_flame_manager entities
function FlameManager::FlameThink() {

	local now = Time()
	local dt = now - lastTime
	lastTime = now

	for ( local slot = 0; slot < max_particles; slot++ ) { 

		local spawnTick = GetPropIntArray( self, "m_nSpawnTime", slot )
		local particle = particles[slot]
		if ( !spawnTick ) { 

			particles[slot] = null
			continue
		}

		if ( !particle || particle.spawnTick != spawnTick ) { 

			particle = FlameSpawnParticle( self, slot, spawnTick, params )
			particles[slot] = particle
		}

		FlameStepParticle( self, particle, params, dt )
	}

	if ( dt > 0.0 )
		FlameDamageBosses( self, this )

	return -1
}

// Finds tf_flame_manager entities
function FlameManager::ThinkTable::FlameManagerScanThink() { 

	for ( local manager; manager = Entities.FindByClassname( manager, "tf_flame_manager" ); ) { 

		if ( manager.IsEFlagSet( EFL_SKIPME ) )
			continue

		manager.ValidateScriptScope()

		local scope = manager.GetScriptScope()
		scope.particles  <- array( FLAME_POINT_COUNT )
		scope.max_particles 	 <- FLAME_POINT_COUNT
		scope.lastBurn 			 <- {}
		scope.params 			 <- FlameReadParams( manager )
		scope.lastTime 	 <- Time()
		scope.FlameStepParticle  <- FlameStepParticle.bindenv( FlameManager )
		scope.FlameDamageBosses  <- FlameDamageBosses.bindenv( FlameManager )
		scope.FlameSpawnParticle <- FlameSpawnParticle.bindenv( FlameManager )

		scope.FlameThink <- FlameThink.bindenv( scope )

		AddThinkToEnt( manager, "FlameThink" )

		manager.AddEFlags( EFL_SKIPME )
	}

	return -1
}