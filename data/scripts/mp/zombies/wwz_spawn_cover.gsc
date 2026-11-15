main()
{
    level thread watch_connections();
    println( "[wwz-mod] Registered the Zombies first-spawn cover" );
}

watch_connections()
{
    for (;;)
    {
        level waittill( "connected", player );

        if ( !isbot( player ) )
            player thread signal_pending_spawn();
    }
}

signal_pending_spawn()
{
    self endon( "disconnect" );
    self endon( "spawned_player" );
    level endon( "game_ended" );
    logged = 0;

    // Until the first spawn finishes, the player is a spectator. spawnclient and spawnplayer set
    // these flags while the spawn waits, mostly for the client to stream its weapons. A late joiner
    // who must wait for the next round sets none, so the HUD cover stays off for them.
    for (;;)
    {
        if ( common_scripts\utility::_id_562E( self.waitingtospawn ) || common_scripts\utility::_id_562E( self.waitingtospawnamortize ) || common_scripts\utility::_id_562E( self.loadingplayerweapons ) )
        {
            self _meth_85EF( &"wwz_first_spawn_pending", 0 );

            if ( !logged )
            {
                logged = 1;
                println( "[wwz-mod] Signaled a pending first spawn" );
            }
        }

        wait 0.2;
    }
}
