main()
{
    // Both sandbag walls lead onto the same wooden deck.
    routes = [ "pf1619_auto2108", "pf1694_auto2108", "pf1717_auto2108", "pf1621_auto2108", "pf1692_auto2108" ];
    aligned = 0;
    foreach ( node in getnodearray( "traverse", "targetname" ) )
    {
        if ( !common_scripts\utility::array_contains( routes, node.target ) )
            continue;

        landing = getnode( node.target, "targetname" );
        if ( !isdefined( landing ) )
            continue;

        floor = getgroundposition( landing.origin, 15, 32, 32, 0 );
        if ( !isdefined( floor ) )
            continue;

        // Keep the authored climb height. Anchor its end to the top of the planks.
        node.wwz_walkway_start = node.origin + ( 0, 0, floor[2] - landing.origin[2] );
        aligned++;
    }

    if ( aligned )
        replacefunc( maps\mp\agents\humanoid\_humanoid_traverse::_id_4392, ::traverse_start );
    println( "[wwz-mod] Aligned " + aligned + " of " + routes.size + " Pack-a-Punch walkway climbs" );
}

traverse_start( node, radius )
{
    if ( isdefined( node.wwz_walkway_start ) )
        return node.wwz_walkway_start;

    // Stock start position for all other climbs.
    if ( node.type == "Begin 3D" )
        return node.origin + ( 0, 0, -16 );

    floor = getgroundposition( node.origin, radius, 32, 32, 0 );
    if ( isdefined( floor ) )
        return floor;
    return node.origin;
}
