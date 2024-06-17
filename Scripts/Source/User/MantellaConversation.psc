Scriptname MantellaConversation extends Quest hidden

Import F4SE
Import Utility

Topic property MantellaDialogueLine auto
MantellaRepository property repository auto
MantellaConstants property mConsts auto
Spell property MantellaSpell auto
bool property conversationIsEnding auto

CustomEvent MantellaConversation_Action_mantella_reload_conversation
CustomEvent MantellaConversation_Action_mantella_end_conversation
CustomEvent MantellaConversation_Action_mantella_npc_offended
CustomEvent MantellaConversation_Action_mantella_npc_forgiven
CustomEvent MantellaConversation_Action_mantella_npc_follow

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;           Globals           ;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

Form[] _actorsInConversation
String[] _ingameEvents
String[] _extraRequestActions
bool _does_accept_player_input = false
int DictionaryCleanTimer


event OnInit()
    DictionaryCleanTimer = 10
    _actorsInConversation = new Form[0]
    _ingameEvents = new String[0]
    _extraRequestActions = new String[0]
    RegisterForExternalEvent("OnHttpReplyReceived","OnHttpReplyReceived")
    RegisterForExternalEvent("OnHttpErrorReceived","OnHttpErrorReceived")
    ;mConsts.EVENT_ACTIONS + mConsts.ACTION_RELOADCONVERSATION <- Does not work in Fallout4. Needs to be a raw string 
    ; RegisterForCustomEvent(self, "MantellaConversation_Action_mantella_reload_conversation")
    ; RegisterForCustomEvent(self, "MantellaConversation_Action_mantella_end_conversation")
endEvent

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;    Start new conversation   ;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

function StartConversation(Actor[] actorsToStartConversationWith)
    if(actorsToStartConversationWith.Length > 2)
        Debug.Notification("Can not start conversation. Conversation is already running.")
        return
    endIf

    _actorsInConversation = new Form[0]
    _ingameEvents = new string[0]
    _extraRequestActions = new string[0]
    UpdateActorsArray(actorsToStartConversationWith)

    if(actorsToStartConversationWith.Length < 2)
        Debug.Notification("Not enough characters to start a conversation")
        return
    endIf

    int handle = F4SE_HTTP.createDictionary()
    F4SE_HTTP.setString(handle, mConsts.KEY_REQUESTTYPE, mConsts.KEY_REQUESTTYPE_STARTCONVERSATION)
    AddCurrentActorsAndContext(handle)
    F4SE_HTTP.sendLocalhostHttpRequest(handle, mConsts.HTTP_PORT, mConsts.HTTP_ROUTE_MAIN)
    string address = "http://localhost:" + mConsts.HTTP_PORT + "/" + mConsts.HTTP_ROUTE_MAIN
    Debug.Notification("Sent StartConversation http request to " + address)  
endFunction

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;    Continue conversation    ;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

Function AddActorsToConversation(Actor[] actorsToAdd)
    UpdateActorsArray(actorsToAdd)    
EndFunction

function OnHttpReplyReceived(int typedDictionaryHandle)
    string replyType = F4SE_HTTP.getString(typedDictionaryHandle, mConsts.KEY_REPLYTYPE ,"error")
    If (replyType != "error")
        ContinueConversation(typedDictionaryHandle)        
    Else
        string errorMessage = F4SE_HTTP.getString(typedDictionaryHandle, "mantella_message","Error: Could not retrieve error message")
        Debug.Notification(errorMessage)
        CleanupConversation()
    EndIf
endFunction

function ContinueConversation(int handle)
    string nextAction = F4SE_HTTP.getString(handle, mConsts.KEY_REPLYTYPE, "Error: Did not receive reply type")
    ; Debug.Notification(nextAction)
    if(nextAction == mConsts.KEY_REPLYTTYPE_STARTCONVERSATIONCOMPLETED)
        RequestContinueConversation()
    elseIf(nextAction == mConsts.KEY_REPLYTYPE_NPCTALK)
        int npcTalkHandle = F4SE_HTTP.getNestedDictionary(handle, mConsts.KEY_REPLYTYPE_NPCTALK)
        ProcessNpcSpeak(npcTalkHandle)
        RequestContinueConversation()
    elseIf(nextAction == mConsts.KEY_REPLYTYPE_PLAYERTALK)
        If (repository.microphoneEnabled)
            Debug.Notification("Listening...")
            sendRequestForVoiceTranscribe()
        Else
            Debug.Notification("Awaiting player text input...")
            _does_accept_player_input = True
        EndIf
    elseIf (nextAction == mConsts.KEY_REQUESTTYPE_TTS)
        string transcribe = F4SE_HTTP.getString(handle, mConsts.KEY_TRANSCRIBE, "*Complete gibberish*")
        if repository.allowVision
            repository.GenerateMantellaVision()
        endif
        sendRequestForPlayerInput(transcribe)
        repository.ResetEventSpamBlockers() ;reset spam blockers to allow the Listener Script to pick up on those again
        Debug.Notification("Thinking...")
        
    elseIf(nextAction == mConsts.KEY_REPLYTYPE_ENDCONVERSATION)
        CleanupConversation()
    endIf
endFunction

function RequestContinueConversation()
    int handle = F4SE_HTTP.createDictionary()
    F4SE_HTTP.setString(handle, mConsts.KEY_REQUESTTYPE, mConsts.KEY_REQUESTTYPE_CONTINUECONVERSATION)
    AddCurrentActorsAndContext(handle)
    if(_extraRequestActions && _extraRequestActions.Length > 0)
        Debug.Notification("_extraRequestActions contains items. Sending them along with continue!")
        F4SE_HTTP.setStringArray(handle, mConsts.KEY_REQUEST_EXTRA_ACTIONS, _extraRequestActions)
        ClearExtraRequestAction()
        Debug.Notification("_extraRequestActions got cleared. Remaining items: " + _extraRequestActions.Length)
    endif
    F4SE_HTTP.sendLocalhostHttpRequest(handle, mConsts.HTTP_PORT, mConsts.HTTP_ROUTE_MAIN)
endFunction

function ProcessNpcSpeak(int handle)
    string speakerName = F4SE_HTTP.getString(handle, mConsts.KEY_ACTOR_SPEAKER, "Error: No speaker transmitted for action 'NPC talk'")
    ;Debug.Notification("Transmitted speaker name: "+ speakerName)
    Actor speaker = GetActorInConversation(speakerName)
    ;Debug.Notification("Chosen Actor: "+ speaker.GetDisplayName())
    if speaker != none
        string lineToSpeak = F4SE_HTTP.getString(handle, mConsts.KEY_ACTOR_LINETOSPEAK, "Error: No line transmitted for actor to speak")
        float duration = F4SE_HTTP.getFloat(handle, mConsts.KEY_ACTOR_DURATION, 0)
        string[] actions = F4SE_HTTP.getStringArray(handle, mConsts.KEY_ACTOR_ACTIONS)        
        RaiseActionEvent(speaker, lineToSpeak, actions)
        NpcSpeak(speaker, lineToSpeak, Game.GetPlayer(), duration)
    endIf
endFunction

function NpcSpeak(Actor actorSpeaking, string lineToSay, Actor actorToSpekTo, float duration)
    ; MantellaSubtitles.SetInjectTopicAndSubtitleForSpeaker(actorSpeaking, MantellaDialogueLine, lineToSay)
    actorSpeaking.Say(MantellaDialogueLine, abSpeakInPlayersHead=false)
    actorSpeaking.SetLookAt(actorToSpekTo)
    if repository.notificationsSubtitlesEnabled
        debug.notification(actorSpeaking.GetDisplayName()+":"+lineToSay)
    endif
    float durationAdjusted = duration - 0.5
    if(durationAdjusted < 0)
        durationAdjusted = 0
    endIf
    Utility.Wait(durationAdjusted)
endfunction

Actor function GetActorInConversation(string actorName)      
    int i = 0
    While i < _actorsInConversation.Length
        Actor currentActor = _actorsInConversation[i] as Actor
        if currentActor.GetDisplayName() == actorName
            return currentActor
        endIf
        i += 1
    EndWhile
    return none
endFunction



;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;       End conversation      ;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

Function EndConversation()
    int handle = F4SE_HTTP.createDictionary()
    F4SE_HTTP.setString(handle, mConsts.KEY_REQUESTTYPE,mConsts.KEY_REQUESTTYPE_ENDCONVERSATION)
    F4SE_HTTP.sendLocalhostHttpRequest(handle, mConsts.HTTP_PORT, mConsts.HTTP_ROUTE_MAIN)
EndFunction

Function CleanupConversation()
    conversationIsEnding = true
    _does_accept_player_input = false
    DispelAllMantellaMagicEffectsFromActors()
    StartTimer(4,DictionaryCleanTimer)  ;starting timer with ID 10 for 4 seconds
    Debug.Notification("Conversation has ended!")  
    Stop()
EndFunction


Event Ontimer( int TimerID)
    if TimerID==DictionaryCleanTimer
        ;Spacing how the cleaning of dictionaries because the game crashes on some setups when it's called directly in CleanupConversation()
        Debug.trace("Timer elapsed : Cleaning dictionnaries")
        F4SE_HTTP.clearAllDictionaries() 
        conversationIsEnding = false
    Endif
Endevent


Function DispelAllMantellaMagicEffectsFromActors()
    int i=0
    
    While i < _actorsInConversation.Length
        Actor actorToDispel = _actorsInConversation[i] as actor
        actorToDispel.DispelSpell(MantellaSpell)
        i += 1
    EndWhile
Endfunction
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;   Handle player speaking    ;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

function sendRequestForPlayerInput(string playerInput)
    AddIngameEvent(repository.constructPlayerState())
    int handle = F4SE_HTTP.createDictionary()
    F4SE_HTTP.setString(handle, mConsts.KEY_REQUESTTYPE, mConsts.KEY_REQUESTTYPE_PLAYERINPUT)
    F4SE_HTTP.setString(handle, mConsts.KEY_REQUESTTYPE_PLAYERINPUT, playerinput)
    int[] handlesNpcs = BuildNpcsInConversationArray()
    F4SE_HTTP.setNestedDictionariesArray(handle, mConsts.KEY_ACTORS, handlesNpcs)    
    int handleContext = BuildContext()
    F4SE_HTTP.setNestedDictionary(handle, mConsts.KEY_CONTEXT, handleContext)

    ClearIngameEvent()    
    F4SE_HTTP.sendLocalhostHttpRequest(handle, mConsts.HTTP_PORT, mConsts.HTTP_ROUTE_MAIN)
endFunction

function sendRequestForVoiceTranscribe()
    int handle = F4SE_HTTP.createDictionary()
    F4SE_HTTP.setString(handle, mConsts.KEY_REQUESTTYPE, mConsts.KEY_REQUESTTYPE_TTS)
    string[] namesInConversation = new string[_actorsInConversation.Length]
    int i = 0
    While i < _actorsInConversation.Length
        namesInConversation[i] = (_actorsInConversation[i] as Actor).GetDisplayName()
        i += 1
    EndWhile
    F4SE_HTTP.setStringArray(handle, mConsts.KEY_INPUT_NAMESINCONVERSATION, namesInConversation)
    F4SE_HTTP.sendLocalhostHttpRequest(handle, mConsts.HTTP_PORT, mConsts.HTTP_ROUTE_STT)
endFunction

function GetPlayerTextInput(string entrytype)
    ;disable for VR
    if entryType == "playerResponseTextEntry" && _does_accept_player_input
        TIM:TIM.Open(1,"Enter Mantella text dialogue","", 2, 250)
        RegisterForExternalEvent("TIM::Accept","SetPlayerResponseTextInput")
        RegisterForExternalEvent("TIM::Cancel","NoTextInput")
    elseif entryType == "gameEventEntry"
        TIM:TIM.Open(1,"Enter Mantella a new game event log","", 2, 250)
        RegisterForExternalEvent("TIM::Accept","SetGameEventTextInput")
        RegisterForExternalEvent("TIM::Cancel","NoTextInput")
    endif
endFunction

Function SetPlayerResponseTextInput(string text)
    ;disable for VR
    ;Debug.notification("This text input was entered "+ text)
    UnRegisterForExternalEvent("TIM::Accept")
    UnRegisterForExternalEvent("TIM::Cancel")
    if repository.allowVision
        repository.GenerateMantellaVision()
    endif
    sendRequestForPlayerInput(text)
    _does_accept_player_input = False
    repository.ResetEventSpamBlockers() ;reset spam blockers to allow the Listener Script to pick up on those again
    Debug.Notification("Thinking...")
EndFunction

Function SetGameEventTextInput(string text)
    ;disable for VR
    ;Debug.notification("This text input was entered "+ text)
    UnRegisterForExternalEvent("TIM::Accept")
    UnRegisterForExternalEvent("TIM::Cancel")
    AddIngameEvent(text)
EndFunction

    ;
Function NoTextInput(string text)
    ;disable for VR
    ;Debug.notification("Text input cancelled")
    UnRegisterForExternalEvent("TIM::Accept")
    UnRegisterForExternalEvent("TIM::Cancel")
EndFunction

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;       Action handler        ;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

Function RaiseActionEvent(Actor speaker, string lineToSpeak, string[] actions)
    if(!actions || actions.Length == 0)
        return ;dont send out an action event if there are no actions to act upon
    endIf

    int i = 0
    While i < actions.Length
        string extraAction = actions[i]
        Debug.Notification("Received action " + extraAction + ". Sending out event!")
        TriggerCorrectCustomEvent(extraAction, speaker, lineToSpeak)
        i += 1
    EndWhile    
EndFunction

Function TriggerCorrectCustomEvent(string actionIdentifier, Actor speaker, string lineToSpeak)
    Var[] kargs = new Var[2]
    kargs[0] = speaker
    kargs[1] = lineToSpeak
    if(actionIdentifier == mConsts.ACTION_RELOADCONVERSATION)
        SendCustomEvent("MantellaConversation_Action_mantella_reload_conversation", kargs)
        TriggerReloadConversation()        
    ElseIf (actionIdentifier == mConsts.ACTION_ENDCONVERSATION)
        SendCustomEvent("MantellaConversation_Action_mantella_end_conversation", kargs)
        EndConversation()
    ElseIf (actionIdentifier == mConsts.ACTION_NPC_OFFENDED)
        SendCustomEvent("MantellaConversation_Action_mantella_npc_offended", kargs)
    ElseIf (actionIdentifier == mConsts.ACTION_NPC_FORGIVEN)
        SendCustomEvent("MantellaConversation_Action_mantella_npc_forgiven", kargs)
    ElseIf (actionIdentifier == mConsts.ACTION_NPC_FOLLOW)
        SendCustomEvent("MantellaConversation_Action_mantella_npc_follow", kargs)
    endIf
endFunction

Function AddExtraRequestAction(string extraAction)
    if(!_extraRequestActions)
        _extraRequestActions = new string[0]
    endif
    _extraRequestActions.Add(extraAction)
EndFunction

Function ClearExtraRequestAction()
    _extraRequestActions.Clear()
EndFunction

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;        Ingame events        ;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

Function AddIngameEvent(string eventText)
    if(!_ingameEvents)
        _ingameEvents = new string[0]
    endif
    _ingameEvents.Add(eventText)
EndFunction

Function ClearIngameEvent()
    _ingameEvents.Clear()
EndFunction

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; Action: Reload conversation ;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

function TriggerReloadConversation()
    Debug.Notification("OnReloadConversationActionReceived triggered")
    AddExtraRequestAction(mConsts.ACTION_RELOADCONVERSATION)
endFunction

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;       Error handling        ;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

function OnHttpErrorReceived(int typedDictionaryHandle)
    string errorMessage = F4SE_HTTP.getString(typedDictionaryHandle, mConsts.HTTP_ERROR ,"error")
    If (errorMessage != "error")
        Debug.Notification("Received F4SE_HTTP error: " + errorMessage)        
        CleanupConversation()
    Else
        Debug.Notification("Error: Could not retrieve error")
        CleanupConversation()
    EndIf
endFunction

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;            Utils            ;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

bool Function IsPlayerInConversation()
    int i = 0
    While i < _actorsInConversation.Length
        if (_actorsInConversation[i] == Game.GetPlayer())
            return true
        endif
        i += 1
    EndWhile
    return false    
EndFunction

Bool function IsActorInConversation(Actor ActorRef)      
    int i = 0
    While i < _actorsInConversation.Length
        Actor currentActor = _actorsInConversation[i] as Actor
        if currentActor == ActorRef
            return true
        endIf
        i += 1
    EndWhile
    return false
endFunction

Function UpdateActorsArray(Actor[] actorsToUpdate)
    int i = 0    
    While i < actorsToUpdate.Length
        int pos = _actorsInConversation.Find(actorsToUpdate[i])
        if(pos < 0)
            _actorsInConversation.Add(actorsToUpdate[i])
        endIf
        i += 1
    EndWhile
EndFunction

int Function CountActorsInConversation()
    return _actorsInConversation.Length
EndFunction

Actor Function GetActorInConversationByIndex(int indexOfActor) 
    If (indexOfActor >= 0 && indexOfActor < _actorsInConversation.Length)
        return _actorsInConversation[indexOfActor] as Actor
    EndIf
    return none
EndFunction

Function AddCurrentActorsAndContext(int handleToAddTo)
    ;Add Actors
    int[] handlesNpcs = BuildNpcsInConversationArray()
    F4SE_HTTP.setNestedDictionariesArray(handleToAddTo, mConsts.KEY_ACTORS, handlesNpcs)
    ;add context
    int handleContext = BuildContext()
    F4SE_HTTP.setNestedDictionary(handleToAddTo, mConsts.KEY_CONTEXT, handleContext)
EndFunction

int[] function BuildNpcsInConversationArray()
    int[] actorHandles =  new int[_actorsInConversation.Length]
    int i = 0
    While i < _actorsInConversation.Length
        actorHandles[i] = buildActorSetting(_actorsInConversation[i] as Actor)
        i += 1
    EndWhile
    return actorHandles
endFunction

int function buildActorSetting(Actor actorToBuild)    
    int handle = F4SE_HTTP.createDictionary()
    F4SE_HTTP.setInt(handle, mConsts.KEY_ACTOR_ID, (actorToBuild.getactorbase() as form).getformid())
    F4SE_HTTP.setString(handle, mConsts.KEY_ACTOR_NAME, actorToBuild.GetDisplayName())
    F4SE_HTTP.setBool(handle, mConsts.KEY_ACTOR_ISPLAYER, actorToBuild == game.getplayer())
    F4SE_HTTP.setInt(handle, mConsts.KEY_ACTOR_GENDER, actorToBuild.getleveledactorbase().getsex())
    F4SE_HTTP.setString(handle, mConsts.KEY_ACTOR_RACE, actorToBuild.getrace())
    F4SE_HTTP.setInt(handle, mConsts.KEY_ACTOR_RELATIONSHIPRANK, actorToBuild.getrelationshiprank(game.getplayer()))
    F4SE_HTTP.setString(handle, mConsts.KEY_ACTOR_VOICETYPE, actorToBuild.GetVoiceType())
    F4SE_HTTP.setBool(handle, mConsts.KEY_ACTOR_ISINCOMBAT, actorToBuild.IsInCombat())    
    F4SE_HTTP.setBool(handle, mConsts.KEY_ACTOR_ISENEMY, actorToBuild.getcombattarget() == game.GetPlayer())
    int customValuesHandle = BuildCustomActorValues(actorToBuild)
    F4SE_HTTP.setNestedDictionary(handle, mConsts.KEY_ACTOR_CUSTOMVALUES, customValuesHandle)  
    return handle
endFunction

int Function BuildCustomActorValues(Actor actorToBuildCustomValuesFor)
    int handleCustomActorValues = F4SE_HTTP.createDictionary()
    F4SE_HTTP.setFloat(handleCustomActorValues, mConsts.KEY_ACTOR_CUSTOMVALUES_POSX, actorToBuildCustomValuesFor.getpositionX())
    F4SE_HTTP.setFloat(handleCustomActorValues, mConsts.KEY_ACTOR_CUSTOMVALUES_POSY, actorToBuildCustomValuesFor.getpositionY())
    return handleCustomActorValues
EndFunction

int function BuildContext()
    int handle = F4SE_HTTP.createDictionary()
    String currLoc = ""
    form currentLocation = game.getplayer().GetCurrentLocation() as Form
    if currentLocation
        currLoc = currentLocation.getName()
    Else
        currLoc = "Boston area"
    endIf
    F4SE_HTTP.setString(handle, mConsts.KEY_CONTEXT_LOCATION, currLoc)
    F4SE_HTTP.setInt(handle, mConsts.KEY_CONTEXT_TIME, GetCurrentHourOfDay())
    F4SE_HTTP.setStringArray(handle, mConsts.KEY_CONTEXT_INGAMEEVENTS, _ingameEvents)
    int customValuesHandle = BuildCustomContextValues()
    F4SE_HTTP.setNestedDictionary(handle, mConsts.KEY_CONTEXT_CUSTOMVALUES, customValuesHandle)
    return handle
endFunction

int Function BuildCustomContextValues()
    int handleCustomContextValues = F4SE_HTTP.createDictionary()
    Actor player = game.getplayer()  
    F4SE_HTTP.setFloat(handleCustomContextValues, mConsts.KEY_CONTEXT_CUSTOMVALUES_PLAYERPOSX, player.getpositionX())
    F4SE_HTTP.setFloat(handleCustomContextValues, mConsts.KEY_CONTEXT_CUSTOMVALUES_PLAYERPOSY, player.getpositionY())
    F4SE_HTTP.setFloat(handleCustomContextValues, mConsts.KEY_CONTEXT_CUSTOMVALUES_PLAYERROT, player.GetAngleZ())
    F4SE_HTTP.setBool(handleCustomContextValues, mConsts.KEY_CONTEXT_CUSTOMVALUES_VISION_READY, repository.allowVision)
    return handleCustomContextValues
EndFunction



int function GetCurrentHourOfDay()
	float Time = Utility.GetCurrentGameTime()
	Time -= Math.Floor(Time) ; Remove "previous in-game days passed" bit
	Time *= 24 ; Convert from fraction of a day to number of hours
	int Hour = Math.Floor(Time) ; Get whole hour
	return Hour
endFunction