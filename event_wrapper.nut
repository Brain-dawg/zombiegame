// Event hook/callback wrapper
// - SM-style event hooking
// - Dynamically adding/removing hooks at runtime, automatically handles re-collection
// - Configurable call ordering of events regardless of file include order

// __CollectEventCallbacks internally does something similar, appending functions to an array and then calling them in order.
// This effectively stuffs an array of functions into the first available cell for a given event hook array.
// Call order for events is handled by this script instead of vscript_server.nut.

// TODO: Performance benchmarks.
// We use this to dynamically add/remove events at potentially critical times ( large piles of bot spawns mostly )
// So far I haven't seen any PERF WARNINGS in console using this, some bot tags may yell on bot/player spawn.
__CREATE_SCOPE( "__zevents", "ZEvents" )

/**************************************************************************************************************
 * If MAX_EVENT_FUNCTABLES is 8 and you try to do                                                             *
 *                                                                                                            *
 *     PZI_EVENT( "player_death", "PlayerDeath", @( params ) printl( params.userid ), 10 )                    *
 *                                                                                                            *
 * you will get errors 				                                                                          *
 *                                                                                                            *
 * extensions can simply re-define this to whatever they want/need                                            *
 * this is the amount of iterations the event wrapper will do to look for functions to call on a given event  *
 * so don't set it to something unnecessarily high.                                                           *
 **************************************************************************************************************/
const MAX_EVENT_FUNCTABLES = 8

// event call ordering
// these ensure the core library has a consistent call ordering, regardless of include order.
const EVENT_WRAPPER_MAIN = 0
const EVENT_WRAPPER_UTIL = 1

ZEvents.EventsPreCollect <- {}
ZEvents.CollectedEvents  <- {}

if ( !( "TableId" in ZEvents ) )
    ZEvents.TableId <- UniqueString( "_Compiled" )

function ZEvents::_OnDestroy() {

    if ( "HOOK_EVENT" in ROOT )
        delete ::HOOK_EVENT

    ClearEvents( null )
}

function ZEvents::AddRemoveEventHook( event, funcname, func = null, index = "unordered", manual_collect = false ) {

    // remove hook
    if ( !func ) {

        if ( event in EventsPreCollect ) {

            // direct index removal
            if ( index in EventsPreCollect[ event ] && funcname in EventsPreCollect[ event ][ index ] )

                delete EventsPreCollect[ event ][ index ][ funcname ]

            // wildcard funcname
            if ( index in EventsPreCollect[ event ] && endswith( funcname, "*" ) )

                foreach( name, func in EventsPreCollect[ event ][ index ] )

                    if ( funcname == "*" || startswith( name, funcname.slice( 0, -1 ) ) )

                        delete EventsPreCollect[ event ][ index ][ name ]

            // invalid index, look for funcname in any index
            else if ( !( index in EventsPreCollect[ event ] ) )

                foreach( idx, func_table in EventsPreCollect[ event ] )

                    if ( funcname in func_table )

                        delete EventsPreCollect[ event ][ idx ][ funcname ]

            // stil nothing, look for funcname in any event
            else

                foreach( e, event_table in EventsPreCollect )

                    foreach( idx, func_table in event_table )

                        if ( funcname in func_table )

                            delete func_table[ funcname ]
        }
        // remove from all EventsPreCollect at a given index
        else if ( event == "*" )

            foreach( e, event_table in EventsPreCollect )

                if ( index in event_table && funcname in event_table[ index ] )

                    delete EventsPreCollect[ e ][ index ][ funcname ]

                else if ( index in event_table && endswith( funcname, "*" ) )

                    foreach( name, func in event_table[ index ] )

                        if ( funcname == "*" || startswith( name, funcname.slice( 0, -1 ) ) )

                            delete event_table[ index ][ name ]
        return
    }

    if ( !( event in EventsPreCollect ) )

        EventsPreCollect[ event ] <- {}

    if ( !( index in EventsPreCollect[ event ] ) )

        EventsPreCollect[ event ][ index ] <- {}

    EventsPreCollect[ event ][ index ][ funcname ] <- func

    // we don't need this internally, feature for external scripts
    // only here if someone wants to register events then collect them manually at a later time
    if ( manual_collect ) return

    ZEvents.CollectEvents()
}

function ZEvents::CollectEvents() {

    local old_table = {}
    local old_table_name = "Z_Events_" + TableId

    if ( old_table_name in CollectedEvents )

        old_table = CollectedEvents[ old_table_name ]

    foreach ( event, new_table in EventsPreCollect ) {

        local call_order = array( MAX_EVENT_FUNCTABLES )

        // set up call order
        foreach ( index, func_table in new_table )

            if ( index != "unordered" )

                call_order[ index ] = func_table

        // add unordered events to the end of the call order
        if ( "unordered" in new_table )

            call_order[ call_order.len() - 1 ] = new_table[ "unordered" ]

        // remove deleted events from the existing table
        foreach ( tbl in call_order )

            foreach ( name, func in tbl || {} )

                if ( name in old_table && !( name in new_table ) )

                    delete old_table[ name ]

        local event_string = event == "OnTakeDamage" ? "OnScriptHook_" : "OnGameEvent_"

        // set up hook table
        // add to old table reference to preserve existing event hooks
        old_table[ event_string + event ] <- function( params ) {

            foreach( i, tbl in call_order )

                foreach( name, func in tbl || {} )

                    if ( func )

                        func( params )
        }
    }

    // copy table to new ID
    local new_id = UniqueString( "_Compiled" )
    local new_table_name = "Z_Events_" + new_id

    // old events are copied to new table to preserve existing event hooks
    CollectedEvents[ new_table_name ] <- old_table

    // remove old table
    if ( old_table_name in CollectedEvents )
        delete CollectedEvents[ old_table_name ]

    // update table ID
    TableId = new_id

    // collect new events
    __CollectGameEventCallbacks( CollectedEvents[ new_table_name ] )
}

function ZEvents::ClearEvents( index = "unordered" ) {

    if ( index == null || index == "*" ) {

        ZEvents.EventsPreCollect <- {}
        ZEvents.CollectedEvents  <- {}
        return
    }

    ZEvents.AddRemoveEventHook( "*", "*", null, index )
}

::HOOK_EVENT <- ZEvents.AddRemoveEventHook.bindenv( ZEvents )

//examples
// HOOK_EVENT( "player_death", "FuncNameHereA", function( params ) {
//     printl( params.userid + " died first" )
// }, 0 )
// HOOK_EVENT( "player_death", "FuncNameHereB", function( params ) {
//     printl( params.userid + " died first" )
// }, 0 )
// HOOK_EVENT( "player_death", "FuncNameHere1", function( params ) {
//     printl( params.userid + " died1" )
// }, 1 )
// HOOK_EVENT( "player_death", "FuncNameHere2", function( params ) {
//     printl( params.userid + " died2" )
// }, 2 )
// HOOK_EVENT( "player_death", "FuncNameHere3", function( params ) {
//     printl( params.userid + " died3" )
// }, 3 )
// HOOK_EVENT( "player_death", "FuncNameHere4", function( params ) {
//     printl( params.userid + " died last" )
// } )
