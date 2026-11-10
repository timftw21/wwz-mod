main()
{
    level endon( "game_ended" );

    // The radio has locked in the fight, and the opening sequence still
    // has to finish before the first combat phase reads these settings.
    level waittill( "players_boss_spawn_done" );

    if ( level.players.size != 1 )
        return;

    phases = level.zmb_island_final_boss_phases;
    difficulty = level.zmb_island_difficulty_settings;

    if ( !isdefined( phases ) || phases.size != 4 || !isdefined( difficulty ) )
    {
        println( "[wwz-mod] Darkest Shore solo finale tuning skipped: stock boss settings are unavailable" );
        return;
    }

    active_bosses = [ 1, 1, 2, 2 ];
    zombie_caps = [ 4, 5, 6, 8 ];

    foreach ( index, phase in phases )
    {
        phase.num_alive = active_bosses[index];
        difficulty["zmb_assassin_boss_health_" + phase.phase_num].func = ::solo_boss_base_health;
        difficulty["zmb_assassin_boss_phase_" + phase.phase_num + "_zombie_count"][0] = zombie_caps[index];
    }

    difficulty["zmb_assassin_boss_fireman_health"].func = ::solo_boss_base_health;
    difficulty["zmb_assassin_boss_num_fire_panels"][0] = 3;
    println( "[wwz-mod] Applied Darkest Shore solo finale tuning at wave " + level.wavecounter );
}

solo_boss_base_health( stock_minimum_wave )
{
    if ( level.players.size != 1 )
        return maps\mp\zquests\casual\island_ee_main::current_fodder_zombie_health( stock_minimum_wave );

    // Use the normal health curve with a lower floor and a ceiling, so
    // entering late does not make the finale an endless ammo check.
    health_wave = int( clamp( level.wavecounter, 15, 24 ) );
    return maps\mp\gametypes\zombies::_id_1E59( undefined, health_wave ) * 0.80;
}
