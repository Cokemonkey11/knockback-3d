
scope test initializer i
    private function c takes nothing returns boolean
        local integer index = 0
        local unit u

        loop
            exitwhen index > 4

            set u = CreateUnit(Player(0), 'hfoo', -512. + 256.*index, 0., 90.)
            call UnitApplyTimedLife(u, 'BTLF', 5.)
            call Knockback3D.add(u, GetRandomReal(300., 1000.), bj_PI/2., GetRandomReal(0., bj_PI/2.))

            set index = index + 1
        endloop

        set u = null
        return false
    endfunction

    private function i takes nothing returns nothing
        local trigger t = CreateTrigger()
        call FogMaskEnable(false)
        call FogEnable(false)
        call TriggerRegisterPlayerEvent(t, Player(0), EVENT_PLAYER_END_CINEMATIC)
        call TriggerAddCondition(t, Condition(function c))
        set t = null
    endfunction
endscope
