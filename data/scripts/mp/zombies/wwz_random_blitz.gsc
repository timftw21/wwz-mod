main()
{
    replacefunc( _id_056A::_id_6F62, ::watch_machine_door );
    replacefunc( _id_056A::_id_7A59, ::reset_machine );
    replacefunc( _id_056A::_id_A149, ::watch_machine_prompt );
    println( "[wwz-mod] Random Blitz uses a 90-second reset with a cooldown prompt" );
}

reset_machine( player )
{
    player endon( "disconnect" );
    player notify( "update_trigger_cost" );
    // Death must not leave the cooldown flag set permanently after a respawn.
    wait 90;
    player.random_blitz_resetting = 0;
    player notify( "update_trigger_cost" );
    println( "[wwz-mod] Random Blitz reset complete" );
}

watch_machine_prompt( player, preserve_prompt )
{
    player endon( "disconnect" );
    previous_resetting = undefined;
    for (;;)
    {
        self _id_056A::_id_6F5E( player, preserve_prompt );
        if ( self.perkname == "perk_random" )
        {
            resetting = common_scripts\utility::_id_562E( player.random_blitz_resetting );
            // The stock interaction payload reserves its low 16 bits for the cost.
            // Send cooldown in bit 16, scoped to Random Blitz, through that same HUD path.
            if ( resetting )
                self._id_65DC._id_6F56 = self._id_65DC._id_6F56 | ( 1 << 16 );
            self._id_65DC.interact_disabled = resetting;
            self._id_65DC._id_6642 = 1;
            if ( !isdefined( previous_resetting ) || previous_resetting != resetting )
                println( "[wwz-mod] Random Blitz scripted cooldown prompt: " + resetting );
            previous_resetting = resetting;
        }
        player common_scripts\utility::waittill_any( "perk_discount_applied", "used_vending_machine_discount",
            "update_trigger_cost", "perkmachine_activated", "take_perk" );
    }
}

#using_animtree("destructibles");

watch_machine_door( player )
{
    player endon( "disconnect" );
    opened = 0;
    random_blitz = self.perkname == "perk_random";
    react_distance = 250000;
    if ( isdefined( level.blitz_react_dist_override ) )
        react_distance = level.blitz_react_dist_override;

    if ( !random_blitz && common_scripts\utility::_id_562E( level.blitz_always_open ) )
    {
        wait 0.25;
        self._id_82EF setscriptablepartstate( "machine_main", "opening" );
        wait( getanimlength( %zmb_perk_machine_open ) );
        self._id_82EF setscriptablepartstate( "machine_main", "opened" );
        return;
    }

    for (;;)
    {
        wait 0.25;
        buying = common_scripts\utility::_id_562E( player._id_5799 );
        affordable = player.moneycurrent >= _id_056A::_id_4602( player, self );
        nearby = self _id_056A::should_open_based_on_distance( player, react_distance );

        if ( random_blitz )
        {
            resetting = common_scripts\utility::_id_562E( player.random_blitz_resetting );
            // Let an already-open machine finish its purchase animation after payment.
            // This never opens a closed machine while the player is buying another Blitz.
            if ( opened && buying )
                continue;

            should_open = nearby && affordable && !resetting;
        }
        else
        {
            should_open = !player _id_056A::_id_4B7E( self.perkname ) && nearby && ( affordable || buying )
                || isdefined( level.perk_machine_should_open ) && [[ level.perk_machine_should_open ]]( self );
        }

        if ( opened == should_open )
            continue;

        if ( should_open )
        {
            player.wasperkgreeted = 1;
            sound = _id_0380::_id_2889( "zmb_perk_machine_open", undefined, self.origin + ( 0, 0, 100 ) );
            _id_0378::_id_8D14( sound );
            self._id_82EF setscriptablepartstate( "machine_main", "opening" );
            wait( getanimlength( %zmb_perk_machine_open ) );
            self._id_82EF setscriptablepartstate( "machine_main", "opened" );
        }
        else
        {
            sound = _id_0380::_id_2889( "zmb_perk_machine_close", undefined, self.origin + ( 0, 0, 100 ) );
            _id_0378::_id_8D14( sound );
            self._id_82EF setscriptablepartstate( "machine_main", "closing" );
            wait( getanimlength( %zmb_perk_machine_reverse ) );
            self._id_82EF setscriptablepartstate( "machine_main", "closed" );
        }

        if ( random_blitz )
            println( "[wwz-mod] Random Blitz door open: " + should_open + ", affordable: " + affordable
                + ", resetting: " + common_scripts\utility::_id_562E( player.random_blitz_resetting ) );
        opened = should_open;
    }
}
