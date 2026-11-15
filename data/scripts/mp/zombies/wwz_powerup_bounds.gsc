main()
{
    replacefunc( maps\mp\gametypes\zombies::_id_3B9B, ::find_pickup_spot );
    println( "[wwz-mod] Registered the Zombies power-up bounds check" );
}

// Stock findValidPickupSpot moves a drop away from nearby players with navmesh queries, and only
// the killed zombie's origin was checked against the enabled zones. Zombies count as entered after
// their first traversal, and zone volumes and the navmesh both reach past barricades, so a drop
// could land on the zombies' side of one. This keeps the stock choices and order, but every spot
// must also be reachable by a player; otherwise the drop moves back toward the nearest player.
find_pickup_spot( origin )
{
    near_range = 80;
    near_squared = near_range * near_range;
    setdvarifuninitialized( "debugPickupDrop", 0 );
    level notify( "findValidPickupSpot" );
    near = [];
    close = [];
    alive = [];

    foreach ( player in level.players )
    {
        if ( maps\mp\_utility::isreallyalive( player ) )
        {
            distance = distance2dsquared( origin, player.origin );

            if ( distance < near_squared )
                near[near.size] = player;

            if ( distance < 40000 )
                close[close.size] = player;

            alive[alive.size] = player;
        }
    }

    reach = new_reach( origin );

    if ( near.size == 0 )
    {
        if ( in_bounds( origin, reach ) )
            return origin;

        return relocate( origin, origin, alive, near_squared, reach );
    }

    center = ( 0, 0, 0 );

    foreach ( player in close )
        center = center + player.origin;

    center = center / close.size;
    offset = ( center[0], center[1], origin[2] ) - origin;
    offset_length = length( offset );

    // Stock divides by this length; a player standing exactly on the drop would stop the thread.
    if ( offset_length == 0 )
    {
        offset = ( 1, 0, 0 );
        offset_length = 1;
    }

    rejected = undefined;
    spot = _func_2E1( origin + offset * -1 * ( near_range / offset_length ) );

    if ( isdefined( spot ) && maps\mp\gametypes\zombies::_id_991E( spot, close, near_squared, origin ) )
    {
        if ( in_bounds( spot, reach ) )
            return spot;

        rejected = spot;
    }

    search = origin;

    if ( isdefined( spot ) && !_func_2DC( origin, spot ) )
        search = spot;

    foreach ( candidate in _func_2E0( search, 140, 16 ) )
    {
        if ( !maps\mp\gametypes\zombies::_id_991E( candidate, alive, near_squared ) )
            continue;

        if ( in_bounds( candidate, reach ) )
        {
            if ( isdefined( rejected ) )
                println( "[wwz-mod] Moved a power-up from " + rejected + " (" + bounds_problem( rejected, reach ) + ") to " + candidate );

            return candidate;
        }

        if ( !isdefined( rejected ) )
            rejected = candidate;
    }

    if ( isdefined( rejected ) )
        return relocate( origin, rejected, alive, near_squared, reach );

    return undefined;
}

new_reach( origin )
{
    reach = spawnstruct();
    reach.origin = origin;
    reach.players = [];
    nearest = undefined;

    foreach ( player in level.players )
    {
        if ( !isalive( player ) || player.sessionstate != "playing" )
            continue;

        point = _func_2E1( player.origin );

        if ( !isdefined( point ) )
            continue;

        reach.players[reach.players.size] = point;
        distance = distance2dsquared( point, origin );

        if ( !isdefined( nearest ) || distance < nearest )
        {
            nearest = distance;
            reach.nearest = point;
        }
    }

    // Only drops near the fighting sit across a barricade from the players. Far kills, such as
    // trap kills, keep the stock zone check rather than risk a long-range line test.
    reach.near_fight = isdefined( nearest ) && nearest <= 800 * 800;
    return reach;
}

reachable( spot, reach )
{
    if ( !reach.near_fight )
        return 1;

    // The navmesh is cut at barricades and zombies cross them on traversal links, so a navmesh
    // trace from a player stops there while the open play area stays connected.
    foreach ( point in reach.players )
    {
        if ( !_func_2DC( point, spot ) )
            return 1;
    }

    // Around a corner: one intermediate navmesh point a player can reach in a straight line.
    if ( !isdefined( reach.hubs ) )
        reach.hubs = reach_hubs( reach );

    foreach ( hub in reach.hubs )
    {
        if ( !_func_2DC( hub, spot ) )
            return 1;
    }

    return 0;
}

reach_hubs( reach )
{
    samples = _func_2E0( reach.origin, 240, 12 );

    foreach ( point in reach.players )
    {
        foreach ( sample in _func_2E0( point, 320, 6 ) )
            samples[samples.size] = sample;
    }

    hubs = [];

    foreach ( sample in samples )
    {
        foreach ( point in reach.players )
        {
            if ( !_func_2DC( point, sample ) )
            {
                hubs[hubs.size] = sample;
                break;
            }
        }
    }

    return hubs;
}

relocate( origin, rejected, alive, near_squared, reach )
{
    problem = bounds_problem( rejected, reach );

    if ( !isdefined( reach.nearest ) )
    {
        println( "[wwz-mod] Dropped no power-up at " + rejected + " (" + problem + "); no player to walk back toward" );
        return undefined;
    }

    // Walk back from the drop toward the nearest player. The first in-bounds spot is on the
    // player's side of whatever cut it off, such as a barricade.
    fallback = undefined;

    for ( step = 1; step <= 10; step++ )
    {
        sample = _func_2E1( origin + ( reach.nearest - origin ) * ( step / 10.0 ) );

        if ( !isdefined( sample ) || !in_bounds( sample, reach ) )
            continue;

        if ( maps\mp\gametypes\zombies::_id_991E( sample, alive, near_squared ) )
        {
            println( "[wwz-mod] Moved a power-up from " + rejected + " (" + problem + ") back to " + sample );
            return sample;
        }

        if ( !isdefined( fallback ) )
            fallback = sample;
    }

    // Every spot on the way is next to a player; look around the first in-bounds one instead.
    if ( isdefined( fallback ) )
    {
        foreach ( candidate in _func_2E0( fallback, 140, 16 ) )
        {
            if ( maps\mp\gametypes\zombies::_id_991E( candidate, alive, near_squared ) && in_bounds( candidate, reach ) )
            {
                println( "[wwz-mod] Moved a power-up from " + rejected + " (" + problem + ") near " + candidate );
                return candidate;
            }
        }
    }

    println( "[wwz-mod] Dropped no power-up at " + rejected + " (" + problem + "); no in-bounds spot nearby" );
    return undefined;
}

in_zone( spot )
{
    // Enabled zones only: a closed-off area is out of bounds for the players too.
    return !isdefined( level.zone_data ) || maps\mp\zombies\_zombies_zone_manager::ispointinanyzone( spot + ( 0, 0, 1 ), 1 ) || maps\mp\zombies\_zombies_zone_manager::ispointinanyzone( spot + ( 0, 0, 20 ), 1 );
}

on_navmesh( spot )
{
    // Players walk the navmesh, so the spot must lie on it rather than on a ledge or in the air.
    floor = _func_2E1( spot );
    return isdefined( floor ) && distance2dsquared( floor, spot ) <= 256 && abs( floor[2] - spot[2] ) <= 32;
}

in_bounds( spot, reach )
{
    return isdefined( spot ) && in_zone( spot ) && on_navmesh( spot ) && reachable( spot, reach );
}

bounds_problem( spot, reach )
{
    if ( !in_zone( spot ) )
        return "outside the enabled zones";

    if ( !on_navmesh( spot ) )
        return "off the navmesh";

    if ( !reachable( spot, reach ) )
        return "unreachable from the players";

    return "too close to a player";
}
