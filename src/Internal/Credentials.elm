module Internal.Credentials exposing (..)

{-| The Credentials type is the keychain that stores all tokens, values,
numbers and other types that need to be remembered.

This file combines the internal functions with the API endpoints to create a fully functional Credentials keychain.

-}

import Dict
import Internal.Api.Task as Api
import Internal.Api.CredUpdate exposing (CredUpdate(..))
import Internal.Context as Context exposing (Context)
import Internal.Event as Event
import Internal.Room as Room
import Internal.Tools.Exceptions as X
import Internal.Values.Credentials as Internal
import Internal.Values.Event as IEvent
import Internal.Values.Room as IRoom
import Internal.Values.StateManager as StateManager
import Task exposing (Task)


{-| You can consider the `Credentials` type as a large ring of keys,
and Elm will figure out which key to use.
If you pass the `Credentials` into any function, then the library will look for
the right keys and tokens to get the right information.
-}
type Credentials
    = Credentials
        { cred : Internal.ICredentials
        , context : Context
        }


{-| Get a Credentials type based on an unknown access token.

This is an easier way to connect to a Matrix homeserver, but your access may end
when the access token expires, is revoked or something else happens.

-}
fromAccessToken : { baseUrl : String, accessToken : String } -> Credentials
fromAccessToken { baseUrl, accessToken } =
    Context.fromBaseUrl baseUrl
        |> Context.addToken accessToken
        |> (\context ->
                { cred = Internal.init, context = context }
           )
        |> Credentials


{-| Get a Credentials type using a username and password.
-}
fromLoginCredentials : { username : String, password : String, baseUrl : String } -> Credentials
fromLoginCredentials { username, password, baseUrl } =
    Context.fromBaseUrl baseUrl
        |> Context.addUsernameAndPassword
            { username = username
            , password = password
            }
        |> (\context ->
                { cred = Internal.init, context = context }
           )
        |> Credentials


{-| Get a room based on its id.
-}
getRoomById : String -> Credentials -> Maybe Room.Room
getRoomById roomId (Credentials { cred, context }) =
    Internal.getRoomById roomId cred
        |> Maybe.map (Room.withContext context)


{-| Insert an internal room type into the credentials.
-}
insertInternalRoom : IRoom.IRoom -> Credentials -> Credentials
insertInternalRoom iroom (Credentials data) =
    Credentials { data | cred = Internal.insertRoom iroom data.cred }


{-| Internal a full room type into the credentials.
-}
insertRoom : Room.Room -> Credentials -> Credentials
insertRoom =
    Room.withoutContext >> insertInternalRoom


{-| Update the Credentials type with new values
-}
updateWith : CredUpdate -> Credentials -> Credentials
updateWith credUpdate ((Credentials ({ cred, context } as data)) as credentials) =
    case credUpdate of
        MultipleUpdates updates ->
            List.foldl updateWith credentials updates

        GetEvent input output ->
            case getRoomById input.roomId credentials of
                Just room ->
                    output
                        |> Event.initFromGetEvent
                        |> Room.addInternalEvent
                        |> (|>) room
                        |> insertRoom
                        |> (|>) credentials

                Nothing ->
                    credentials

        -- TODO
        InviteSent _ _ ->
            credentials

        JoinedMembersToRoom _ _ ->
            credentials

        -- TODO
        MessageEventSent _ _ ->
            credentials
        
        -- TODO
        RedactedEvent _ _ ->
            credentials

        -- TODO
        StateEventSent _ _ ->
            credentials

        -- TODO
        SyncUpdate input output ->
            let
                jRooms : List IRoom.IRoom
                jRooms =
                    output.rooms
                        |> Maybe.map .join
                        |> Maybe.withDefault Dict.empty
                        |> Dict.toList
                        |> List.map
                            (\( roomId, jroom ) ->
                                case getRoomById roomId credentials of
                                    -- Update existing room
                                    Just room ->
                                        case jroom.timeline of
                                            Just timeline ->
                                                room
                                                    |> Room.withoutContext
                                                    |> IRoom.addEvents
                                                        { events =
                                                            List.map
                                                                (Event.initFromClientEventWithoutRoomId roomId)
                                                                timeline.events
                                                        , limited = timeline.limited
                                                        , nextBatch = output.nextBatch
                                                        , prevBatch =
                                                            timeline.prevBatch
                                                                |> Maybe.withDefault
                                                                    (Maybe.withDefault "" input.since)
                                                        , stateDelta =
                                                            jroom.state
                                                                |> Maybe.map
                                                                    (.events
                                                                        >> List.map (Event.initFromClientEventWithoutRoomId roomId)
                                                                        >> StateManager.fromEventList
                                                                    )
                                                        }

                                            Nothing ->
                                                Room.withoutContext room

                                    -- Add new room
                                    Nothing ->
                                        jroom
                                            |> Room.initFromJoinedRoom { nextBatch = output.nextBatch, roomId = roomId }
                            )
            in
            cred
                |> Internal.addSince output.nextBatch
                |> List.foldl Internal.insertRoom
                |> (|>) jRooms
                |> (\x -> { cred = x, context = context })
                |> Credentials

        UpdateAccessToken token ->
            Credentials { data | context = Context.addToken token context }

        UpdateVersions versions ->
            Credentials { data | context = Context.addVersions versions context }

        -- TODO: Save all info
        LoggedInWithUsernameAndPassword _ output ->
            Credentials { data | context = Context.addToken output.accessToken context }


{-| Synchronize credentials
-}
sync : Credentials -> Task X.Error CredUpdate
sync (Credentials { cred, context }) =
    Api.sync
        { accessToken = Context.accessToken context
        , baseUrl = Context.baseUrl context
        , filter = Nothing
        , fullState = Nothing
        , setPresence = Nothing
        , since = Internal.getSince cred
        , timeout = Just 30
        , versions = Context.versions context
        }


{-| Get a list of all synchronised rooms.
-}
rooms : Credentials -> List Room.Room
rooms (Credentials { cred, context }) =
    cred
        |> Internal.getRooms
        |> List.map (Room.withContext context)
