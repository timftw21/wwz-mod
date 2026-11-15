main()
{
    level thread track_players();
    println( "[wwz-mod] Registered the Zombies scoreboard downs column" );
}

track_players()
{
    foreach ( player in level.players )
        player thread track_downs();

    for (;;)
    {
        level waittill( "connected", player );
        player thread track_downs();
    }
}

track_downs()
{
    self notify( "wwz_track_downs" );
    self endon( "wwz_track_downs" );
    self endon( "disconnect" );

    // Zombies never counts deaths (_damage skips them for zombie games), so the scoreboard's deaths
    // field carries the last-stand count; the report reads the same value from pers["deaths"].
    for (;;)
    {
        self waittill( "begin_last_stand" );
        // The last-stand handler counts the down right after this notify.
        waittillframeend;

        if ( !isdefined( self._id_6882 ) )
            continue;

        self.deaths = self._id_6882;
        self.pers["deaths"] = self._id_6882;
    }
}
