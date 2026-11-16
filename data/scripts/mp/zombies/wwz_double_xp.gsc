main()
{
    // 1356.gsc (Zombies rank) caches this scale at init from the playlist dvars, which the bundled
    // playlist sets to 2. It multiplies match XP and also gates the Double XP splash.
    replacefunc( _id_054C::getzmxpscale, ::xp_scale );
    level.zmxpscale = xp_scale();

    if ( level.zmxpscale > 1 )
        println( "[wwz-mod] Zombies Double XP enabled by the host" );
    else
        println( "[wwz-mod] Zombies Double XP disabled by the host" );
}

// wwz_zm_double_xp (WWZ-MOD Options) on the host. getzmxpscale also caps the scale at 2.
xp_scale()
{
    if ( getdvarint( "wwz_zm_double_xp", 1 ) )
        return 2;

    return 1;
}
