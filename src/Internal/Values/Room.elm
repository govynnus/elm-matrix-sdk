module Internal.Values.Room exposing (..)

import Dict exposing (Dict)
import Internal.Tools.Hashdict as Hashdict exposing (Hashdict)
import Internal.Tools.SpecEnums exposing (SessionDescriptionType(..))
import Internal.Values.Event exposing (BlindEvent, IEvent)
import Internal.Values.StateManager as StateManager exposing (StateManager)
import Internal.Values.Timeline as Timeline exposing (Timeline)
import Json.Encode as E


type IRoom
    = IRoom
        { accountData : Dict String E.Value
        , ephemeral : List BlindEvent
        , events : Hashdict IEvent
        , roomId : String
        , timeline : Timeline
        }


{-| Get given account data from the room.
-}
accountData : String -> IRoom -> Maybe E.Value
accountData key (IRoom room) =
    Dict.get key room.accountData


{-| Add the data of a single event to the hashdict of events.
-}
addEvent : IEvent -> IRoom -> IRoom
addEvent event (IRoom ({ events } as room)) =
    IRoom { room | events = Hashdict.insert event events }


{-| Add new events as the most recent events.
-}
addEvents :
    { events : List IEvent
    , limited : Bool
    , nextBatch : String
    , prevBatch : String
    , stateDelta : Maybe StateManager
    }
    -> IRoom
    -> IRoom
addEvents ({ events } as data) (IRoom room) =
    IRoom
        { room
            | events = List.foldl Hashdict.insert room.events events
            , timeline = Timeline.addNewEvents data room.timeline
        }


{-| Get an event by its id.
-}
getEventById : String -> IRoom -> Maybe IEvent
getEventById eventId (IRoom room) =
    Hashdict.get eventId room.events


getStateEvent : { eventType : String, stateKey : String } -> IRoom -> Maybe IEvent
getStateEvent data (IRoom room) =
    room.timeline
        |> Timeline.mostRecentState
        |> StateManager.getStateEvent data


{-| Insert account data into the room.
-}
insertAccountData : Dict String E.Value -> IRoom -> IRoom
insertAccountData newdata (IRoom room) =
    IRoom { room | accountData = Dict.union newdata room.accountData }


{-| Insert a chunk of events into a room.
-}
insertEvents :
    { events : List IEvent
    , nextBatch : String
    , prevBatch : Maybe String
    , stateDelta : Maybe StateManager
    }
    -> IRoom
    -> IRoom
insertEvents data (IRoom ({ timeline } as room)) =
    IRoom
        { room | timeline = Timeline.insertEvents data timeline }
        |> List.foldl addEvent
        |> (|>) data.events


{-| Get the latest gap.
-}
latestGap : IRoom -> Maybe { from : Maybe String, to : String }
latestGap (IRoom room) =
    Timeline.latestGap room.timeline


{-| Get the most recent events.
-}
mostRecentEvents : IRoom -> List IEvent
mostRecentEvents (IRoom room) =
    Timeline.mostRecentEvents room.timeline


{-| Get the room's id.
-}
roomId : IRoom -> String
roomId (IRoom room) =
    room.roomId
