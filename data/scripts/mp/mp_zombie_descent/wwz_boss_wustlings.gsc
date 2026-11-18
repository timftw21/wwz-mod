main()
{
    replacefunc( maps\mp\zombies\zombie_king::manage_respawn, ::manage_respawn );
    println( "[wwz-mod] Final boss Wustlings respawn one at a time" );
}

// Each boss-fight zombie respawns in its own slot; Wustling slots now take turns.
manage_respawn( type )
{
    spawners = common_scripts\utility::getstructarray( "zone_citadel_spawners", "targetname" );
    wustling = type == "zombie_heavy";

    for (;;)
    {
        if ( wustling )
            wait_for_wustling_turn();

        zombie = maps\mp\zombies\_zombies::_id_90BA( type, common_scripts\utility::random( spawners ), "final boss fight", 0, 1, 1 );

        if ( !isdefined( zombie ) )
        {
            wait 1;
            continue;
        }

        while ( isdefined( zombie.health ) && zombie.health > 0 )
            waitframe();

        wait( maps\mp\zombies\zombie_king::get_respawn_times() );
    }
}

wait_for_wustling_turn()
{
    logged = 0;

    while ( wustling_present() )
    {
        if ( !logged )
        {
            logged = 1;
            println( "[wwz-mod] Final boss Wustling waiting for the present one" );
        }

        wait 0.5;
    }

    // Count this Wustling as present until its spawn finishes.
    level.wwz_wustling_reserved = gettime();
}

wustling_present()
{
    if ( isdefined( level.wwz_wustling_reserved ) && gettime() - level.wwz_wustling_reserved < 1000 )
        return 1;

    foreach ( zombie in maps\mp\zombies\_util::_id_4090( "zombie_heavy" ) )
    {
        if ( isalive( zombie ) )
            return 1;
    }

    return 0;
}
