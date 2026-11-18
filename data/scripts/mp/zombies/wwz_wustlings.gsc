main()
{
    // Fraction of the round table's Wustlings carried until a whole one is cut.
    level.wwz_wustling_cut = 0;

    // 1389.gsc is the round spawner.
    replacefunc( _id_056D::_id_76A8, ::build_round_spawns );
    replacefunc( _id_056D::_id_220F, ::next_round_spawn );
    replacefunc( _id_056D::should_override_follower_spawn, ::should_replace_wustling );
    println( "[wwz-mod] Round Wustlings spawn one at a time and 25% less often" );
}

build_round_spawns( wave )
{
    spawns = [];
    scheduled = 0;
    cut = 0;

    foreach ( type, count in _id_056D::_id_4743( wave ) )
    {
        if ( type == "zombie_heavy" )
        {
            scheduled = count;
            level.wwz_wustling_cut = level.wwz_wustling_cut + count * 0.25;
            cut = int( level.wwz_wustling_cut );
            level.wwz_wustling_cut = level.wwz_wustling_cut - cut;
        }

        for ( index = 0; index < count; index++ )
        {
            // Cut Wustlings become regular zombies, so the round keeps its size.
            if ( type == "zombie_heavy" && index < cut )
                spawns[spawns.size] = "zombie_generic";
            else
                spawns[spawns.size] = type;
        }
    }

    if ( scheduled > 0 )
        println( "[wwz-mod] Round " + wave + " spawns " + ( scheduled - cut ) + " of " + scheduled + " Wustlings" );

    return common_scripts\utility::array_randomize( spawns );
}

next_round_spawn()
{
    // Stock order: recycled zombies first, then the current round's queue.
    if ( level._id_ABEC maps\mp\_utility::_id_5DCB() > 0 )
        return level._id_ABEC maps\mp\_utility::_id_5DCA();

    if ( level._id_ABED maps\mp\_utility::_id_5DCB() > 0 )
        return level._id_ABED maps\mp\_utility::_id_5DCA();

    _id_056D::_id_7B87();

    if ( level._id_AC12 maps\mp\_utility::_id_5DCB() == 0 )
        return undefined;

    // The spawner waits a second and asks again.
    if ( hold_wustling( level._id_AC12 ) )
    {
        // Dropping emptied the queue: queue the next round as stock does after a round's last spawn,
        // which lets this round end.
        if ( level._id_AC12 maps\mp\_utility::_id_5DCB() == 0 )
            _id_056D::_id_7B87();

        return undefined;
    }

    spawn = level._id_AC12 maps\mp\_utility::_id_5DCA();

    if ( spawn._id_AC0B == "zombie_heavy" )
    {
        // Count this Wustling as present until its spawn finishes.
        level.wwz_wustling_reserved = gettime();

        if ( common_scripts\utility::_id_562E( level.wwz_wustling_delayed ) )
        {
            level.wwz_wustling_delayed = 0;
            println( "[wwz-mod] Released a delayed round Wustling" );
        }
    }

    return spawn;
}

hold_wustling( queue )
{
    next = queue.head.value;

    // A forced type list replaces the type after this, so it needs no delay.
    if ( next._id_AC0B != "zombie_heavy" || isdefined( level._id_1CC0 ) || !wustling_present() )
        return 0;

    if ( !common_scripts\utility::_id_562E( level.wwz_wustling_delayed ) )
    {
        level.wwz_wustling_delayed = 1;
        println( "[wwz-mod] Delaying round Wustlings while another is present" );
    }

    for ( node = queue.head._id_66A1; isdefined( node ); node = node._id_66A1 )
    {
        later = node.value;

        if ( later._id_AC0B == "zombie_heavy" || later._id_A97C != next._id_A97C )
            continue;

        // Trade places with the next other spawn in this round, so the Wustling still comes.
        next._id_AC0B = later._id_AC0B;
        later._id_AC0B = "zombie_heavy";
        return 0;
    }

    // Only Wustlings remain in this round. Living Wustlings do not hold a round open, so once
    // the rest of the round is dead, drop these instead of holding it open.
    if ( !round_has_other_zombies( next._id_A97C ) )
        drop_wustlings( queue, next._id_A97C );

    return 1;
}

// Mirrors the stock round-end check (1389.gsc _id_584C), which skips Wustlings and other
// zombies marked with _id_6816.
round_has_other_zombies( wave )
{
    if ( level._id_6F43 > 0 )
        return 1;

    foreach ( agent in maps\mp\agents\_agent_utility::getactiveagentsoftype( "all" ) )
    {
        if ( common_scripts\utility::_id_562E( agent._id_6816 ) )
            continue;

        if ( isdefined( agent._id_901F ) && agent._id_901F <= wave )
            return 1;
    }

    return 0;
}

drop_wustlings( queue, wave )
{
    dropped = 0;

    while ( queue maps\mp\_utility::_id_5DCB() > 0 )
    {
        spawn = queue.head.value;

        if ( spawn._id_AC0B != "zombie_heavy" || spawn._id_A97C != wave )
            break;

        queue maps\mp\_utility::_id_5DCA();
        dropped++;
    }

    level.wwz_wustling_delayed = 0;
    println( "[wwz-mod] Dropped " + dropped + " round " + wave + " Wustlings because another is alive" );
}

should_replace_wustling( recycled, type )
{
    // Stock kept recycled zombies and capped Wustlings at 2, 3 or 4 by player count.
    // A forced type list can still pick one while another is alive.
    if ( recycled || !isdefined( type ) || type != "zombie_heavy" || wustling_count() == 0 )
        return 0;

    println( "[wwz-mod] Replaced a round Wustling because another is alive" );
    return 1;
}

wustling_present()
{
    if ( isdefined( level.wwz_wustling_reserved ) && gettime() - level.wwz_wustling_reserved < 1000 )
        return 1;

    return wustling_count() > 0;
}

wustling_count()
{
    count = 0;

    foreach ( zombie in maps\mp\zombies\_util::_id_4090( "zombie_heavy" ) )
    {
        if ( isalive( zombie ) )
            count++;
    }

    return count;
}
