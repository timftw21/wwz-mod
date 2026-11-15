main()
{
    if ( !isdefined( treasure_parts() ) )
        return;

    // 1387.gsc's treasure zombie kill reward: one roll from the main table, then a perk roll.
    replacefunc( _id_056B::_id_348E, ::treasure_drop );
    println( "[wwz-mod] Treasure zombies drop missing treasure parts first" );
}

// Each map's treasure parts, as the stock drop table names them, and their character group.
// Part n completes challenge n of that group.
treasure_parts()
{
    parts = spawnstruct();

    switch ( maps\mp\_utility::getmapname() )
    {
        case "mp_zombie_nest_01":
            parts.group = 1; // treasure_set
            parts.names = [ "Hunter piece 1", "Hunter piece 2", "Hunter piece 3", "Hunter piece 4", "Hunter piece 5" ];
            break;
        case "mp_zombie_island":
            parts.group = 12; // hunter_blood_set
            parts.names = [ "Hunter dlc1 piece 1", "Hunter dlc2 piece 2", "Hunter dlc3 piece 3" ];
            break;
        case "mp_zombie_berlin":
            parts.group = 19; // surgeon_set
            parts.names = [ "drop_dlc2_char_a_0", "drop_dlc2_char_a_1", "drop_dlc2_char_a_2" ];
            break;
        default:
            return undefined;
    }

    return parts;
}

treasure_drop( origin )
{
    if ( !drop_missing_part( origin ) )
        _id_056B::_id_3479( level._id_AC09, origin );

    wait 1;
    _id_056B::_id_3479( level._id_AC0A, origin );
}

drop_missing_part( origin )
{
    parts = treasure_parts();
    // Bit n is part n; -1 when the local profile's unlocks are not available.
    owned = wwz_treasure_pieces_owned( parts.group );

    if ( owned < 0 )
    {
        println( "[wwz-mod] Treasure parts unknown; used the stock treasure zombie drop" );
        return 0;
    }

    if ( !isdefined( level.wwz_treasure_parts_dropped ) )
        level.wwz_treasure_parts_dropped = [];

    for ( index = 0; index < parts.names.size; index++ )
    {
        if ( owned & ( 1 << index ) )
            continue;

        // Force each part once per match; if its unlock does not save, later drops roll as stock.
        if ( common_scripts\utility::_id_562E( level.wwz_treasure_parts_dropped[index] ) )
            continue;

        entry = find_drop( parts.names[index] );

        if ( !isdefined( entry ) )
        {
            println( "[wwz-mod] Could not find treasure part drop " + parts.names[index] );
            continue;
        }

        level.wwz_treasure_parts_dropped[index] = 1;
        println( "[wwz-mod] Treasure zombie dropped missing part " + ( index + 1 ) + " of " + parts.names.size );
        _id_056B::_id_3478( origin, entry.callback );
        return 1;
    }

    return 0;
}

find_drop( name )
{
    foreach ( entry in level._id_AC09 )
    {
        if ( isdefined( entry._id_2AF8 ) && entry._id_2AF8 == name )
            return entry;
    }

    return undefined;
}
