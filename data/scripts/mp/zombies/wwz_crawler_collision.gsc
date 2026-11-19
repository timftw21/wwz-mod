main()
{
    replacefunc( maps\mp\zombies\_mutators::startcrawl, ::start_crawl );
    println( "[wwz-mod] Registered 24-unit collision height for crawling zombies" );
}

start_crawl()
{
    self.dismember_crawl = 1;
    maps\mp\agents\humanoid\_humanoid_util::dodgedisable();

    if ( isdefined( self.lungemeleeenabled ) )
        maps\mp\agents\humanoid\_humanoid_util::lungemeleeupdate( 10.0, 240, 120, "attack_lunge_boost", level._effect["boost_lunge"], 1, 255 );

    maps\mp\agents\humanoid\_humanoid_util::leapdisable();
    self scragentallowboost( 0 );
    self scragentsetorienttoground( 1 );
    self scragentsetviewheight( 15 );
    // Radius and full height also identify this capsule to the player movement code.
    self _meth_856C( 12, 24 );
    if ( !isdefined( level.wwz_logged_crawler_bounds ) )
    {
        level.wwz_logged_crawler_bounds = 1;
        println( "[wwz-mod] Applied crawling zombie collision bounds" );
    }

    level.crawlingzombies++;
    thread maps\mp\zombies\_util::_id_AB18( 60 );
    self waittill( "death" );
    level.crawlingzombies--;
}
