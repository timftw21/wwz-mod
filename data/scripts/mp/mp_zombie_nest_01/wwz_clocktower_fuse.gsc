main()
{
    level endon( "game_ended" );

    // Centers of the four copper caps on the stock clocktower.
    level.wwz_clocktower_coils = [
        ( 1164.8, -71.1, 3289 ),
        ( 1280.4, -388.7, 3289 ),
        ( 845.3, -187.4, 3289 ),
        ( 960.9, -505.0, 3289 )
    ];

    level thread maps\mp\_utility::_id_6F74( ::watch_tesla_shots );
    println( "[wwz-mod] Clocktower fuse quest is ready" );
    level waittill( "wwz_clocktower_coils_charged" );
    spawn_fuse();
}

watch_tesla_shots()
{
    if ( !level.wwz_clocktower_coils.size )
        return;

    self endon( "disconnect" );
    level endon( "game_ended" );
    level endon( "wwz_clocktower_coils_charged" );

    for ( ;; )
    {
        self waittill( "missile_fire", missile, weapon );

        if ( isdefined( weapon ) && getweaponbasename( weapon ) == "teslagun_zm" )
            charge_aimed_coil();
    }
}

charge_aimed_coil()
{
    eye = self geteye();
    forward = anglestoforward( self _meth_8566() );
    horizontal = ( forward[0], forward[1], 0 );
    horizontal_length_sq = vectordot( horizontal, horizontal );

    if ( horizontal_length_sq < 0.0001 )
        return;

    // Give distant shots some room around the cap and stem. If a trace hits
    // world geometry, it must still reach the original coil bounds.
    foreach ( coil in level.wwz_clocktower_coils )
    {
        shot_distance = vectordot( coil - eye, horizontal ) / horizontal_length_sq;

        if ( shot_distance <= 0 || shot_distance > 7000 )
            continue;

        aim = eye + forward * shot_distance;

        if ( !is_inside_coil( aim, coil, 36 ) )
            continue;

        trace = bullettrace( eye, aim, 0, self );

        if ( trace["fraction"] < 1 && !is_inside_coil( trace["position"], coil, 0 ) )
            continue;

        level.wwz_clocktower_coils = common_scripts\utility::array_remove( level.wwz_clocktower_coils, coil );
        // The stock charge effect emits for 2.9 seconds.
        playloopedfx( level._effect["zmb_elec_coil_charge"], 3.0, coil, 0, ( 0, 0, 1 ), ( 1, 0, 0 ) );
        self playsound( "zmb_hc_switch_hit" );
        println( "[wwz-mod] Clocktower coil charged at " + coil + ". Remaining: " + level.wwz_clocktower_coils.size );

        if ( !level.wwz_clocktower_coils.size )
            level notify( "wwz_clocktower_coils_charged" );

        return;
    }
}

is_inside_coil( point, coil, padding )
{
    radius = 18 + padding;
    return distance2dsquared( point, coil ) <= radius * radius &&
        point[2] >= coil[2] - 118 - padding && point[2] <= coil[2] + 18 + padding;
}

spawn_fuse()
{
    // The archway floor is at z = 1505, directly below the clocktower.
    fuse = spawn( "script_model", ( 1060, -300, 1513 ) );
    fuse setmodel( "zmb_gp_uber_01" );
    fuse maps\mp\zombies\_util::zombies_make_usable( "Hold ^3[{+activate}]^7 to pick up Pack-a-Punch Fuse" );
    println( "[wwz-mod] Pack-a-Punch Fuse spawned beneath the clocktower" );

    for ( ;; )
    {
        fuse waittill( "player_used", player );

        if ( isplayer( player ) && maps\mp\zombies\_util::isonhumanteam( player ) && maps\mp\_utility::isreallyalive( player ) )
            break;
    }

    fuse maps\mp\zombies\_util::zombies_make_unusable();
    playsoundatpos( fuse.origin, "zmb_pap_fuse" );
    fuse delete();

    common_scripts\utility::flag_set( "flag_fuse_pickedup" );
    common_scripts\utility::flag_set( "teslagun_punch_active" );
    level notify( "pap_state_change" );
    iprintln( "Pack-a-Punch Fuse acquired" );
    println( "[wwz-mod] Pack-a-Punch Fuse collected. Tesla Gun upgrade enabled" );
}
