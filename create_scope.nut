if ( !( "__active_scopes" in ROOT ) )
    ::__active_scopes <- {}

function __CREATE_SCOPE( name, scope_ref = null, entity_ref = null, think_func = null, preserved = true ) {

	local ent = FindByName( null, name )

	if ( !ent || !ent.IsValid() ) {

		ent = CreateByClassname( preserved ? "entity_saucer" : "logic_autosave" )
		SetPropString( ent, STRING_NETPROP_NAME, name )
		ent.ValidateScriptScope()
	}

	if ( ent.GetName() != name ) {
		SetPropString( ent, STRING_NETPROP_NAME, name )
		ent.ValidateScriptScope()
	}

	ent.DisableDraw()
	ent.SetCollisionGroup( COLLISION_GROUP_IN_VEHICLE )
	SetPropBool( ent, STRING_NETPROP_PURGESTRINGS, true )
	__active_scopes[ ent ] <- scope_ref

	local ent_scope = ent.GetScriptScope()

	scope_ref  =  scope_ref  || format( "%sScope", name )
	entity_ref =  entity_ref || format( "%sEntity", name )
	ROOT[ scope_ref ]  <- ent_scope
	ROOT[ entity_ref ] <- ent

	if ( think_func ) {

		// Add the think function directly to the entity
		if ( endswith( typeof think_func, "function" ) ) {

			local think_name = think_func.getinfos().name || format( "%s_Think", name )

			ent_scope[ think_name ] <- think_func
			try { _AddThinkToEnt( ent, think_name ) } catch ( _ ) { AddThinkToEnt( ent, think_name ) }
			return
		}

		ent_scope.ThinkTable <- {}

		// Allows us to use any arbitrary string for the think function name
		// scope.MyFunc <- function() { ... } creates an anonymous function
		// won't show up in the performance counter
		compilestring( format( @"

			local ent = EntIndexToHScript( %d )
			local func_name = %s
			local ent_scope = ent.GetScriptScope()

			function %s() {

				foreach ( func in ent_scope.ThinkTable || {} )
					func.call( ent_scope )
				return -1
			}

			ent_scope[ func_name ] <- %s

		", ent.entindex(), format( "\"%s\"", think_func ), think_func, think_func ) )()

		try { _AddThinkToEnt( ent, think_func ) } catch ( _ ) { AddThinkToEnt( ent, think_func ) }
		// delete ROOT[ think_func ]
	}

	ent_scope.setdelegate( {

		function _newslot( k, v ) {

			if ( k == "_OnDestroy" && _OnDestroy == null )
				_OnDestroy = v
			else if ( k == "_OnCreate" )
				v.call( ent_scope )

			ent_scope.rawset( k, v )

		}

	}.setdelegate( {

			parent     = ent_scope.getdelegate()
			id         = ent.GetScriptId()
			index      = ent.entindex()
			_OnDestroy = null

			function _get( k ) { return parent[k] }

			function _delslot( k ) {

				if ( k == id ) {

					if ( _OnDestroy ) {

						local entity = EntIndexToHScript( index )
						local scope  = entity.GetScriptScope()
						scope.self   <- entity
						_OnDestroy.call( scope )
					}

					if ( scope_ref in ROOT )
						delete ROOT[ scope_ref ]

					if ( entity_ref in ROOT )
						delete ROOT[ entity_ref ]

				}

				delete parent[k]
			}
		} )
	)

	// function InputRunScriptCode() {
	// 	printl( self )
	// 	return true
	// }

	return { Entity = ent, Scope = ent_scope }
}