Scriptname MantellaListenerScript extends ReferenceAlias
Import SUP_F4SEVR
Actor property PlayerRef auto
Weapon property MantellaGun auto

Event OnInit ()
   
   PlayerRef.AddItem(MantellaGun, 1, false)
    
endEvent