main()
{
    level.shouldignoreplayerzombiecallback = ::using_puzzle_station;
    println( "[wwz-mod] Enabled zombie targeting protection at the Shadowed Throne puzzle stations" );
}

using_puzzle_station( player, zombie )
{
    if ( !isplayer( player ) )
        return 0;

    // The quest links the player to the station during use and unlinks on exit.
    anchor = player getlinkedparent();
    if ( !isdefined( anchor ) )
        return 0;

    if ( isdefined( anchor.targetname ) && anchor.targetname == "radio_tuner_player_org" )
        return 1;

    return isdefined( anchor.script_parameters ) &&
        ( anchor.script_parameters == "map_board_player_org" || anchor.script_parameters == "safe_player_org" );
}
