main()
{
    replacefunc( maps\mp\zombies\zombie_assassin_spawner_logic::spawn_an_assassin, ::spawn_an_assassin );
    replacefunc( maps\mp\zombies\zombie_assassin_spawner_logic::respawnanassassinzombie, ::respawn_assassin );
    println( "[wwz-mod] Meuchlers spawn with 20% less health" );
}

// Stock spawn_an_assassin. Its look argument is unused; the look follows the modifier.
spawn_an_assassin( modifier, health, spawner, passive, initial_state, disable_fog_sensitivity, disable_exits, action_overrides, aggro_funcs, disable_crouched_ambush, look, forced_zones )
{
    return spawn_assassin( modifier, health, spawner, passive, initial_state, disable_fog_sensitivity, disable_exits, action_overrides, aggro_funcs, disable_crouched_ambush, forced_zones, 0 );
}

spawn_assassin( modifier, health, spawner, passive, initial_state, disable_fog_sensitivity, disable_exits, action_overrides, aggro_funcs, disable_crouched_ambush, forced_zones, keep_health )
{
    // Meistermeuchlers use a special modifier and the boss look; Meuchlers use neither.
    meistermeuchler = isdefined( modifier ) && modifier != "zombie_assassin";
    hole = maps\mp\zombies\zombie_assassin_spawner_logic::get_valid_assassin_spawner( undefined, meistermeuchler, forced_zones );

    if ( !isdefined( hole ) )
        hole = maps\mp\zombies\zombie_assassin_spawner_logic::get_valid_assassin_spawner( undefined, meistermeuchler, forced_zones, 0 );

    if ( isdefined( spawner ) )
        hole = spawner;

    if ( meistermeuchler )
        look = "boss look";
    else
        look = "default look";

    hole thread maps\mp\zombies\zombie_assassin_spawner_logic::cool_down();
    assassin = maps\mp\zombies\_zombies::_id_90BA( "zombie_assassin", hole, "assassin_spawn", 0, 1, 0, look );

    if ( !isdefined( assassin._id_9024 ) && isdefined( hole.script_flag ) )
        assassin._id_9024 = hole.script_flag;

    if ( isdefined( forced_zones ) )
        assassin.forcedzones = forced_zones;

    if ( isdefined( action_overrides ) )
        assassin.optionalassassinactionoverrides = action_overrides;

    if ( isdefined( initial_state ) )
        assassin.optionalinitialstate = initial_state;

    if ( isdefined( disable_fog_sensitivity ) )
        assassin.optionaldisablefogsensitivity = disable_fog_sensitivity;

    if ( isdefined( disable_exits ) )
        assassin.optionaldisableexits = disable_exits;

    if ( isdefined( aggro_funcs ) )
        assassin.aggrofuncsoverride = aggro_funcs;

    if ( isdefined( disable_crouched_ambush ) )
        assassin.optionaldisablecrouchedambush = disable_crouched_ambush;

    if ( isdefined( health ) )
    {
        assassin.maxhealth = health;
        assassin.health = assassin.maxhealth;
    }
    else if ( assassin.health <= 17500 )
    {
        assassin.maxhealth = 17500;
        assassin.health = assassin.maxhealth;
    }

    // A recycled Meuchler keeps the health it had.
    if ( !meistermeuchler && !keep_health )
    {
        stock_health = assassin.maxhealth;
        assassin.maxhealth = int( stock_health * 0.8 );
        assassin.health = assassin.maxhealth;
        println( "[wwz-mod] Meuchler spawned with " + assassin.maxhealth + " health instead of " + stock_health );
    }

    if ( common_scripts\utility::_id_562E( passive ) )
        assassin maps\mp\zombies\_util::_id_84CB();

    assassin.previoushole = hole;
    assassin.lastassassinspawner = hole;
    assassin maps\mp\zombies\zombie_assassin_spawner_logic::apply_modifier( modifier );
    return assassin;
}

// Stock respawnanassassinzombie, used when a Meuchler is recycled closer to the players.
respawn_assassin()
{
    health = self.health;
    spawners = common_scripts\utility::getstructarray( "zombie_assassin_pagan_room_spawner", "targetname" );

    // The pommel room respawn starts with fresh health, as in stock.
    if ( maps\mp\zombies\zombie_assassin_spawner_logic::everyone_in_pommel_room() )
        spawn_assassin( undefined, undefined, common_scripts\utility::random( spawners ), undefined, "Phase 1: Entrance", 1, 1, undefined, undefined, undefined, undefined, 0 );
    else
        spawn_assassin( undefined, health, undefined, undefined, undefined, undefined, undefined, undefined, undefined, undefined, undefined, 1 );

    maps\mp\zombies\zombie_assassin_spawner_logic::killassassinzombie();
}
