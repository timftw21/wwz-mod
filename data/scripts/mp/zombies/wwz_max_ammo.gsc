main()
{
    replacefunc( maps\mp\gametypes\zombies::activatemaxammo, ::activate_max_ammo );
    println( "[wwz-mod] Registered the Zombies Max Ammo akimbo refill" );
}

activate_max_ammo()
{
    level notify( "maxAmmoPickup" );

    foreach ( player in level.players )
    {
        if ( !maps\mp\zombies\_util::isonhumanteam( player ) || !maps\mp\_utility::isreallyalive( player ) )
            continue;

        maps\mp\gametypes\zombies::refillammozombies( player );
        refill_left_clips( player );
        player maps\mp\gametypes\zombies::playersetem1maxammo();

        if ( isdefined( level._id_08AF ) )
            player [[ level._id_08AF ]]();
    }
}

refill_left_clips( player )
{
    foreach ( weapon in player getweaponslistprimaries() )
    {
        if ( !issubstr( weapon, "akimbo" ) || maps\mp\zombies\_util::isrippedturretweapon( weapon ) ||
            maps\mp\zombies\_util::_id_5862( weapon ) || maps\mp\zombies\_util::iszombieconsumableweapon( weapon ) )
            continue;

        // Use the same hand and clip-size conventions as the stock weapon purchase path.
        player setweaponammoclip( weapon, weaponclipsize( weapon, player ), "left" );
        println( "[wwz-mod] Max Ammo filled the left clip for " + weapon );
    }
}
