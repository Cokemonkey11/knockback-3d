
/**
 * Knockback3D by Cokemonkey11, a projectile motion emulator for unit knockback.
 *
 * Requirements:
 *      Optional IsDestructableTree
 *          Supports both PitzerMike's (http://goo.gl/zZHhGc) and BPower's (http://goo.gl/jGYFQK)
 *          implementation. Use one or none.
 *
 *      IsTerrainWalkable or TerrainPathability
 *          To more accurately detect collisions, you must have either IsTerrainWalkable by Anitarf
 *          and Vexorian (http://goo.gl/bf1wpN) OR TerrainPathability by Rising_Dusk
 *          (http://goo.gl/UTzPdG).
 *
 * API:
 *      constant boolean USE_MOVESPEED_MODIFIERS - Prevent a unit from moving while airborne
 *      constant boolean USE_TREE_CHECKER - Check destructables for trees only before destroying
 *      constant boolean DESTROY_DESTRUCTABLES_ONHIT - Destroy destructables hit by projectiles
 *      constant real CLOCK_PERIOD - how often to iterate through projectile bodies
 *      constant real COEFF_RESTITUTION_GROUND - Fraction of velocity to keep after hitting ground
 *      constant real COEFF_RESTITUTION_DSTRBL - Fraction of velocity to keep after hitting destruc.
 *      constant real FRICTION_ITER_MULTIPLIER - Fraction of velocity to lose while sliding per ite.
 *      constant real GRAVITY - Acceleration rate in units per second per second
 *      constant real MAX_Z_VELOCITY_TO_BOUNCE - The necessary z-velocity to bounce off ground
 *      constant real MIN_Z_VELOCITY_TO_BECOME_AIRBORNE - necessay z-velocity to stop sliding
 *      constant real MIN_FLY_HEIGHT - A height threshold (for floating units)
 *      constant real MIN_FOR_KNOCKBACK - Minimum velocity to maintain knockback (units / second)
 *      constant real MIN_SPEED_FRICTION_FX - The minimum speed to draw friction FX
 *      constant string FRICTION_MODEL - The FX to draw during high-friction sliding.
 *      constant real DESTRUCTABLE_ENUM_RADIUS - Size of square to enumerate destructables.
 *      constant real MIN_VEL_DESTROY_DESTRUCTABLE - Minimum velocity to destroy destructable
 *      constant real MAX_HEIGHT_DESTROY_DESTRUCTABLE - The flying height at which destru. destroyed
 *
 *      Knockback3D.updateMapArea(rect r)
 *      Knockback3D.add(unit,real a, real b, real c) - Apply vector of size a to unit towards b on
 *          the XY plane, and c on the Z axis.
 *      Knockback3D.setVel(unit,real a, real b, real c) - Set unit's knockback vector to a towards b
 *          on the XY plan and c on the Z axis.
 */
library Knockback3D uses optional IsDestructableTree, /*
                      */ optional IsTerrainWalkable,  /*
                      */ optional TerrainPathability

    // =========================================================================
    // Begin Customizable Section
    // =========================================================================
    globals
        // Defines whether units should have their movement speed set to 0 while
        // in motion, and then later back to their "default" speed. If false,
        // units in mid air can still fully control themselves. Warning: This is
        // not a lock-safe crowd-control implementation.
        private constant boolean USE_MOVESPEED_MODIFIERS=true

        // Defines whether the script should check enumerated destructables as
        // being trees or not. If enabled, will only work if IsDestructableTree
        // library is available.
        private constant boolean USE_TREE_CHECKER=true

        // Defines whether to enumerate and destroy destructables in contact
        // with projectile bodies.
        private constant boolean DESTROY_DESTRUCTABLES_ONHIT=true
    endglobals

    /**
     * Object which holds both static and instance knockback data. Not to be
     * modified except in designated CUSTOMIZE areas.
     */
    struct Knockback3D
        // A parameter for controlling the system clock, in seconds. 1/30 runs
        // 30 times per second.
        private static constant real CLOCK_PERIOD=1./30.

        // A measure of velocity retention after colliding with ground. 0.4
        // means 40% retention.
        private static constant real COEFF_RESTITUTION_GROUND=.4

        // How much velocity should be retained after hitting a destructable. A
        // value of .3 means 30% velocity is retained.
        private static constant real COEFF_RESTITUTION_DSTRBL=.3

        // What fraction of velocity should be lost with every iteration of
        // ground friction. Note that simulating an abstraction of friction in
        // units per second overflows real precision numbers. Thus, you must
        // adjust this according to your clock period.
        private static constant real FRICTION_ITER_MULTIPLIER=.15

        // The downward acceleration of units in motion. A value of
        // CLOCK_PERIOD*41.25 means they accelerate downwards by 41.25 units per
        // second.
        private static constant real GRAVITY=CLOCK_PERIOD*45.

        // The minimum fall-speed for a unit to bounce. CLOCK_PERIOD*-300. means
        // that the a unit must be falling at 300 units per second to bounce.
        private static constant real MAX_Z_VELOCITY_TO_BOUNCE=CLOCK_PERIOD*-300.

        // The minimum z-velocity of a unit to have it's flying height changed,
        // instead of simply sliding.
        private static constant real MIN_Z_VELOCITY_TO_BECOME_AIRBORNE=CLOCK_PERIOD*150.

        // This is the minimum height a unit can be at before friction is
        // applied. A value greater than 0 is recommended as some units have a
        // small non-zero flying height.
        private static constant real MIN_FLY_HEIGHT=5.

        // The minimum horizontal velocity a unit can be sliding before the
        // system ignores it. A value of CLOCK_PERIOD*30 means the unit will
        // stop sliding when its slide speed reduces past 30 units per second.
        private static constant real MIN_FOR_KNOCKBACK=CLOCK_PERIOD*30.

        // The minimum speed a sliding unit must be moving to spawn a "friction"
        // effect. A value of CLOCK_PERIOD*180 means the effect is applied while
        // units are moving faster than 180 units per second.
        private static constant real MIN_SPEED_FRICTION_FX=CLOCK_PERIOD*180.

        // The effect model to spawn when a unit's horizontal velocity is
        // greater than MIN_SPEED_FRICTION_FX .
        private static constant string FRICTION_MODEL="Objects\\Spawnmodels\\Undead\\ImpaleTargetDust\\ImpaleTargetDust.mdl"

        // The square size to search for destructables when destroying them.
        // Note that a square's diagonal is Sqrt(2) times bigger than this.
        private static constant real DESTRUCTABLE_ENUM_RADIUS=130.

        // The minimum horizontal velocity a unit must have to destroy a
        // destructable. You can set this to a very high number to disable the
        // feature. A value of CLOCK_PERIOD*300 means the unit must travel at
        // 300 units per second on the XY plane, to destroy obstacles.
        private static constant real MIN_VEL_DESTROY_DESTRUCTABLE=CLOCK_PERIOD*300.

        // The height below which a flying unit is elligible to destroy
        // destructables. Ideally it should be the maximum height of your
        // destructables.
        private static constant real MAX_HEIGHT_DESTROY_DESTRUCTABLE=150.

        // =====================================================================
        // End Customizable Section
        // =====================================================================

        private static constant integer CROW_ID='Arav'

        // A stack size counter.
        private static integer dbIndex=-1

        // Stack of knockback data blobs.
        private static thistype array knockDB

        // Movable location for the getZ shim.
        private static location zLoc=Location(0.,0.)

        // Copies of map boundary co-ordinates.
        private static real mapMinX
        private static real mapMaxX
        private static real mapMinY
        private static real mapMaxY

        // Used to enumerate destructables.
        private static rect destructableRect

        private static timer clock=CreateTimer()


        // For getting the z-height of a co-ordinate pair.
        private static method getZ takes real x, real y returns real
            call MoveLocation(zLoc,x,y)
            return GetLocationZ(zLoc)
        endmethod

        // The callback function when enumerating destructables.
        private static method destructableCallback takes nothing returns nothing
            local destructable des=GetEnumDestructable()
            if GetDestructableLife(des)>0. then
                static if DESTROY_DESTRUCTABLES_ONHIT then
                    static if USE_TREE_CHECKER and LIBRARY_IsDestructableTree then
                        if IsDestructableTree(des) then
                            call KillDestructable(des)
                        endif
                    else
                        call KillDestructable(des)
                    endif
                endif
                set hitDestructable=true
            endif
            set des=null
        endmethod

        // The periodic function which iterates through all objects in flight.
        private static method p takes nothing returns nothing
            local boolean newInMap
            local integer index=0
            local real flyHeight
            local real unitX
            local real unitY
            local real heightDifference
            local real newX
            local real newY
            local real velXY
            local thistype tempDat
            loop
                exitwhen index>dbIndex
                set tempDat=thistype.knockDB[index]
                set unitX=GetUnitX(tempDat.u)
                set unitY=GetUnitY(tempDat.u)
                set newX=unitX+tempDat.delX
                set newY=unitY+tempDat.delY
                set newInMap=newX>mapMinX and newX<mapMaxX and newY>mapMinY and newY<mapMaxY
                set flyHeight=GetUnitFlyHeight(tempDat.u)
                set velXY=(tempDat.delX*tempDat.delX+tempDat.delY*tempDat.delY)
                if flyHeight<MIN_FLY_HEIGHT then
                    if IsTerrainWalkable(newX,newY) and newInMap then
                        call SetUnitX(tempDat.u,unitX+tempDat.delX)
                        call SetUnitY(tempDat.u,unitY+tempDat.delY)
                        if tempDat.delZ<=MIN_FLY_HEIGHT then
                            set tempDat.delX=tempDat.delX*(1.-FRICTION_ITER_MULTIPLIER)
                            set tempDat.delY=tempDat.delY*(1.-FRICTION_ITER_MULTIPLIER)
                            if velXY>MIN_SPEED_FRICTION_FX then
                                call DestroyEffect(AddSpecialEffect(FRICTION_MODEL,unitX,unitY))
                            endif
                        endif
                        static if USE_MOVESPEED_MODIFIERS then
                            call SetUnitMoveSpeed(tempDat.u,GetUnitDefaultMoveSpeed(tempDat.u))
                        endif
                    else
                        set tempDat.delX=0
                        set tempDat.delY=0
                    endif

                    if tempDat.delZ<MAX_Z_VELOCITY_TO_BOUNCE then
                        set tempDat.delZ=tempDat.delZ*-1.*COEFF_RESTITUTION_GROUND
                    endif
                    if tempDat.delZ>MIN_Z_VELOCITY_TO_BECOME_AIRBORNE then
                        call SetUnitFlyHeight(tempDat.u,flyHeight+tempDat.delZ,0)
                        set tempDat.delZ=tempDat.delZ-GRAVITY
                    endif
                elseif newInMap then
                    set tempDat.delZ=tempDat.delZ-GRAVITY
                    set heightDifference=getZ(newX,newY)-getZ(unitX,unitY)
                    call SetUnitFlyHeight(tempDat.u,flyHeight+tempDat.delZ-heightDifference,0)
                    call SetUnitX(tempDat.u,newX)
                    call SetUnitY(tempDat.u,newY)
                    static if USE_MOVESPEED_MODIFIERS then
                        call SetUnitMoveSpeed(tempDat.u,0)
                    endif
                else
                    set tempDat.delX=0
                    set tempDat.delY=0
                endif
                if velXY<MIN_FOR_KNOCKBACK and tempDat.delZ>MAX_Z_VELOCITY_TO_BOUNCE and tempDat.delZ<-1*MAX_Z_VELOCITY_TO_BOUNCE and flyHeight<MIN_FLY_HEIGHT then
                    set knockDB[index]=knockDB[dbIndex]
                    set dbIndex=dbIndex-1
                    call SetUnitFlyHeight(tempDat.u,0,0)
                    static if USE_MOVESPEED_MODIFIERS then
                        call SetUnitMoveSpeed(tempDat.u,GetUnitDefaultMoveSpeed(tempDat.u))
                    endif
                    call tempDat.destroy()
                    set index=index-1
                    if dbIndex<0 then
                        call PauseTimer(clock)
                    endif
                endif
                if velXY>MIN_VEL_DESTROY_DESTRUCTABLE and flyHeight<MAX_HEIGHT_DESTROY_DESTRUCTABLE then
                    set hitDestructable=false
                    call MoveRectTo(destructableRect,newX,newY)
                    call EnumDestructablesInRect(destructableRect,null,function thistype.destructableCallback)
                    if hitDestructable then
                        set tempDat.delX=tempDat.delX*COEFF_RESTITUTION_DSTRBL
                        set tempDat.delY=tempDat.delY*COEFF_RESTITUTION_DSTRBL
                    endif
                endif
                set index=index+1
            endloop
        endmethod

        // Get a unit's stack index.
        private static method getUnitIndexFromStack takes unit u returns integer
            local integer index=0
            local integer returner=-1
            local thistype tempDat
            loop
                // A potential future improvement would be to use optional Table
                // instead of linear search.
                exitwhen index>dbIndex or returner!=-1
                set tempDat=knockDB[index]
                if tempDat.u==u then
                    set returner=index
                endif
                set index=index+1
            endloop
            return returner
        endmethod

        private static method onInit takes nothing returns nothing
            set destructableRect=Rect(-1*DESTRUCTABLE_ENUM_RADIUS,-1*DESTRUCTABLE_ENUM_RADIUS,DESTRUCTABLE_ENUM_RADIUS,DESTRUCTABLE_ENUM_RADIUS)
            set mapMinX=GetRectMinX(bj_mapInitialPlayableArea)
            set mapMaxX=GetRectMaxX(bj_mapInitialPlayableArea)
            set mapMinY=GetRectMinY(bj_mapInitialPlayableArea)
            set mapMaxY=GetRectMaxY(bj_mapInitialPlayableArea)
        endmethod

        /**
         * A function for updating the valid map co-ordinates, in case the playable map area changes
         * dynamically.
         */
        public static method updateMapArea takes rect rct returns nothing
            set thistype.mapMinX=GetRectMinX(rct)
            set thistype.mapMinY=GetRectMinY(rct)
            set thistype.mapMaxX=GetRectMaxX(rct)
            set thistype.mapMaxY=GetRectMaxY(rct)
        endmethod

        /**
         * Add a knockback vector to a unit. If the unit is already in the system, the new vector
         * will be emulated as a secondary knockback source.
         *
         * Parameters:
         *      u: unit to knock back
         *      velocity: speed in units per second at which to knock the unit back
         *      angle: The angle on the XY plane to knock the unit, in radians.
         *      alpha: The angle of attack (z-axis) to knock the unit, in radians (where 0 is no AoA)
         */
        public static method add takes unit u, real velocity, real angle, real alpha returns nothing
            local integer index=getUnitIndexFromStack(u)
            local thistype tempDat
            local real instVel=velocity*CLOCK_PERIOD
            if index==-1 then
                set tempDat=thistype.create()
                set tempDat.u=u
                set tempDat.delX=instVel*Cos(angle)*Cos(alpha)
                set tempDat.delY=instVel*Sin(angle)*Cos(alpha)
                set tempDat.delZ=instVel*Sin(alpha)
                set dbIndex=dbIndex+1
                set knockDB[dbIndex]=tempDat
                if UnitAddAbility(tempDat.u,CROW_ID) then
                    call UnitRemoveAbility(tempDat.u,CROW_ID)
                endif
                if dbIndex==0 then
                    call TimerStart(clock,CLOCK_PERIOD,true,function thistype.p)
                endif
            else
                set tempDat=knockDB[index]
                set tempDat.delX=tempDat.delX+instVel*Cos(angle)*Cos(alpha)
                set tempDat.delY=tempDat.delY+instVel*Sin(angle)*Cos(alpha)
                set tempDat.delZ=tempDat.delZ+instVel*Sin(alpha)
            endif
        endmethod

        /**
         * Set the knockback vector of a unit. If the unit is already in the system, the new vector
         * will replace the old one.
         *
         * Parameters:
         *      u: unit to knock back
         *      velocity: speed in units per second at which to knock the unit back
         *      angle: The angle on the XY plane to knock the unit, in radians.
         *      alpha: The angle of attack (z-axis) to knock the unit, in radians (where 0 is no AoA)
         */
        public static method setVel takes unit u, real velocity, real angle, real alpha returns nothing
            local integer index=getUnitIndexFromStack(u)
            local thistype tempDat
            local real instVel=velocity*CLOCK_PERIOD
            if index==-1 then
            set tempDat=thistype.create()
                set tempDat.u=u
                set tempDat.delX=instVel*Cos(angle)*Cos(alpha)
                set tempDat.delY=instVel*Sin(angle)*Cos(alpha)
                set tempDat.delZ=instVel*Sin(alpha)
                set dbIndex=dbIndex+1
                set knockDB[dbIndex]=tempDat
                if UnitAddAbility(tempDat.u,CROW_ID) then
                    call UnitRemoveAbility(tempDat.u,CROW_ID)
                endif
                if dbIndex==0 then
                    call TimerStart(clock,CLOCK_PERIOD,true,function thistype.p)
                endif
            else
                set tempDat=knockDB[index]
                set tempDat.delX=instVel*Cos(angle)*Cos(alpha)
                set tempDat.delY=instVel*Sin(angle)*Cos(alpha)
                set tempDat.delZ=instVel*Sin(alpha)
            endif
        endmethod


        // Instance Variables.

        // The unit being knocked back.
        private unit u

        // The knockback vector's x, y, and z components.
        private real delX
        private real delY
        private real delZ
    endstruct
endlibrary

/**
 * Add a knockback vector to a unit. If the unit is already in the system, the new vector
 * will be emulated as a secondary knockback source.
 *
 * Parameters:
 *      u: unit to knock back
 *      velocity: speed in units per second at which to knock the unit back
 *      angle: The angle on the XY plane to knock the unit, in radians.
 *      alpha: The angle of attack (z-axis) to knock the unit, in radians (where 0 is no AoA)
 *
 * Deprecated: Use Knockback3D.add() instead.
 */
function Knockback3D_add takes unit u, real velocity, real angle, real alpha returns nothing
    call Knockback3D.add(u,velocity,angle,alpha)
    debug call BJDebugMsg("Warning: Knockback3D_add() called. Use " + /*
        */ "Knockback3D.add() instead.")
endfunction

/**
 * Set the knockback vector of a unit. If the unit is already in the system, the new vector
 * will replace the old one.
 *
 * Parameters:
 *      u: unit to knock back
 *      velocity: speed in units per second at which to knock the unit back
 *      angle: The angle on the XY plane to knock the unit, in radians.
 *      alpha: The angle of attack (z-axis) to knock the unit, in radians (where 0 is no AoA)
 *
 * Deprecated: Use Knockback3D.setVel() instead.
 */
function Knockback3D_setVel takes unit u, real velocity, real angle, real alpha returns nothing
    call Knockback3D.setVel(u,velocity,angle,alpha)
    debug call BJDebugMsg("Warning: Knockback3D_setVal() called. Use " + /*
        */ "Knockback3D.setVel() instead.")
endfunction

/**
 * A function for updating the valid map co-ordinates, in case the playable map area changes
 * dynamically.
 *
 * Deprecated: Use Knockback3D.updateMapArea(r) instead.
 */
function Knockback3D_updateMapArea takes rect r returns nothing
    call Knockback3D.updateMapArea(r)
    debug call BJDebugMsg("Warning: Knockback3D_updateMapArea() called. Use " + /*
        */ "Knockback3D.updateMapArea() instead.")
endfunction
