main()
{
    replacefunc( _id_056A::_id_4602, ::machine_price );
    println( "[wwz-mod] Armor machine price capped at 3000 Jolts before discounts" );
}

machine_price( player, machine )
{
    perk = level._id_6F5C[machine.perkname];
    price = perk.cost;
    if ( machine.perkname == "perk_all" )
        return price;

    if ( isdefined( perk._id_8F63 ) && level.players.size == 1 )
        price = perk._id_8F63;

    if ( machine.perkname == "armor" )
    {
        cap = 3000;
        if ( isdefined( player._id_0F60 ) )
        {
            for ( i = 0; i < player._id_0F60 && price < cap; i++ )
                price = maps\mp\zombies\_util::getincreasedcost( price );
        }
        price = min( price, cap );
    }

    discount = player _id_0578::_id_4717( machine );
    return int( price * discount );
}
