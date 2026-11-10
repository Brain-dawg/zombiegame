function GetItemIndex(item) { return NetProps.GetPropInt(item, "m_AttributeManager.m_Item.m_iItemDefinitionIndex") }

// accepts entity handle, item classname, or itemdef index (e.g. 998 for vaccinator)
function HasItemInLoadout(player, item)
{
	for (local child = player.FirstMoveChild(); child; child = child.NextMovePeer())
		if (child == item || child.GetClassname() == item || (item != -1 && GetItemIndex(child) == item))
			return child
}

function TrixButton()
{

    local theclass = activator.GetPlayerClass()
    EmitSoundOn("common/wpn_select.wav", activator)

    if (theclass == 9)
    {
        // don't give the revolver if the player already has it
        if (HasItemInLoadout(activator, "tf_weapon_revolver"))
            return

        ClientPrint(activator, 3, "\x01This \x07FF3F3FRevolver \x01provides \x0799CCFF+65% faster switch time\x01.")
        ClientPrint(activator, 3, "\x01Perfect \x0799CCFFaccuracy \x01if equipped with \x07FF3F3FGunslinger\x01.")
        local gun3 = GiveWeapon(activator, "tf_weapon_revolver", 24, "spy")
        gun3.AddAttribute("hidden secondary max ammo penalty", 0.12, -1)
        gun3.AddAttribute("deploy time decreased", 0.35, -1)
        NetProps.SetPropIntArray(activator, "localdata.m_iAmmo", 24, 2)

        local gun3_vm = NetProps.GetPropEntity(gun3, "m_hExtraWearableViewModel")
        gun3_vm.SetModel("models/workshop/player/items/engineer/taunt_texan_trickshot/taunt_texan_trickshot.mdl")

        local gunslinger = HasItemInLoadout(activator, "tf_weapon_robot_arm")

        if (gunslinger)
            gunslinger.AddCustomAttribute("weapon spread bonus", 0, -1)
    }
}