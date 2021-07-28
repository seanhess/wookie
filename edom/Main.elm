module Main exposing (..)

import Browser exposing (UrlRequest, Document)
import Browser.Navigation as Browser exposing (Key)
import Url exposing (Url)
import Html exposing (Html, div, text, node, Attribute, span)
import Html.Attributes as Html exposing (id)
import Html.Events as Html
import Html.Parser as Parser exposing (Node(..))
import Http exposing (Response)
import Dict exposing (Dict)
import Json.Encode as Encode
import Json.Decode as Decode

-- TODO switch to forms, submit or submit1!
-- TODO try checkboxes, I want to do something on each click
-- TODO connect to actual backend


-- var currentUrl = window.location.pathname + window.location.search

  -- // TODO titles
  -- if (pageUrl != currentUrl) {
  --   let title = "Wookie Tab Title"
  --   console.log(" - ", "pageUrl", pageUrl)
  --   window.history.pushState({pageUrl: pageUrl}, title, pageUrl)
  -- }

    -- method: "POST",
    -- headers: {"Accept": "application/vdom"},
    -- body: body

type alias Id = String
type alias Value = String

type Error
  = FailedParse
  | MissingParamsHeader
  | ServerError ServerError

type ServerError
  = BadUrl
  | Timeout
  | NetworkError
  | BadStatus Http.Metadata String


type alias Action = String



type alias Model =
  { html : String
  , parsed : Result Error (Html Msg)
  , updates : Dict Action Value
  , url : Url
  , key : Key
  }

main : Program String Model Msg
main =
  Browser.application
    { init = init
    , update = update
    , subscriptions = subscriptions
    , view = view
    , onUrlRequest = onUrlRequest
    , onUrlChange = UrlChange
    }

type Msg
  = ServerAction Action 
  | ServerUpdate Action Value
  | Loaded (Result Error (String, String))
  | UrlChange Url
  | None

subscriptions : Model -> Sub Msg
subscriptions _ =
  Sub.none

onUrlRequest : UrlRequest -> Msg
onUrlRequest _ = None


-- "render" the existing html as it stands, and stand by for updates
init : String -> Url -> Key -> (Model, Cmd Msg)
init start url key =
  ( { html = start
    , updates = Dict.empty
    , parsed = parseHtml start
    , key = key
    , url = url
    }
  , Cmd.none
  )


onResponse : Response String -> Result Error (String, String)
onResponse response =
  case response of
    Http.GoodStatus_ meta body ->
      case Dict.get "x-params" meta.headers of
        Nothing -> Err MissingParamsHeader
        Just p -> Ok (p, body)

    Http.BadUrl_ _ ->
      Err <| ServerError BadUrl

    Http.Timeout_ ->
      Err <| ServerError Timeout

    Http.NetworkError_ ->
      Err <| ServerError NetworkError

    Http.BadStatus_ m b ->
      Err <| ServerError <| BadStatus m b
    


serializeValueAction : Action -> Value -> String
serializeValueAction act val =
  (act ++ " " ++ Encode.encode 0 (Encode.string val))


update : Msg -> Model -> (Model, Cmd Msg)
update msg model =
  case msg of

    ServerUpdate action value ->
      ( { model | updates = Dict.insert action value model.updates }
      , Cmd.none
      )

    ServerAction action ->
      let updates = Dict.foldl (\act val items -> serializeValueAction act val :: items) [] model.updates
          body = String.join "\n" (updates ++ [action])
      in ( { model | updates = Dict.empty }
         , Http.request
            { method = "POST"
            , headers = [Http.header "accept" "application/vdom"]
            , url = Url.toString model.url
            , body = Http.stringBody "text/plain" body
            , timeout = Nothing
            , tracker = Nothing
            , expect = Http.expectStringResponse Loaded onResponse
            }
         )

    Loaded (Ok (params, content)) ->
      ( { model | html = content, parsed = parseHtml content }
      ,  Browser.pushUrl model.key (pageUrl model.url params)
      )

    Loaded (Err e) ->
      ( { model | parsed = Err e}
      , Cmd.none
      )

    UrlChange url ->
      ( { model | url = url }
      , Cmd.none
      )

    None ->
      (model, Cmd.none)


-- use the current url, but add the params
pageUrl : Url -> String -> String
pageUrl url params =
  Url.toString { url | query = Just <| "p=" ++ params }


view : Model -> Document Msg
view model =
  -- let test = div [] [ text "Elm Initialized" ]
  { title = "Titulo"
  , body =
      [ case model.parsed of
          Ok content -> content
          Err e -> viewError e
      ]
  }

viewError : Error -> Html Msg
viewError e =
  div []
    [ span [] [ text "Error: " ]
    , span []
       [ case e of
          FailedParse -> text "Failed Parse"
          MissingParamsHeader -> text "Missing Params from Server"
          ServerError BadUrl -> text "Bad url"
          ServerError Timeout -> text "Timeout"
          ServerError NetworkError -> text "Network Error"
          ServerError (BadStatus m b) -> text "Bad Status"
       ]
    ]
 





parseHtml : String -> Result Error (Html Msg)
parseHtml input = 
  case (Parser.run input) of
    Err _ -> Err FailedParse
    Ok nodes -> Ok <|
      div [ id "wookie-root-content"] <|
        List.map toHtml nodes



type alias ElementName = String
type alias AttributeName = String
type alias AttributeValue = String


toHtml : Node -> Html Msg
toHtml node =
  case node of
    (Text s) ->
      text s
    (Comment _) ->
      text ""
    (Element name atts childs) ->
      toElement name atts childs



toElement : ElementName -> List Parser.Attribute -> List Parser.Node -> Html Msg
toElement name atts childs =
  let convertedAtts = List.map toAttribute atts
      convertedChilds = List.map toHtml childs
  in case (name, idFromAttributes atts) of
    -- ("input", Just id) ->
    --   Html.node name (inputListener id :: convertedAtts) convertedChilds
    _ -> 
      Html.node name convertedAtts convertedChilds


-- IF you have an id attribute, yes
-- inputListener : String -> Html.Attribute Msg
-- inputListener id =
--     Html.onInput (Input id)

idFromAttributes : List Parser.Attribute -> Maybe String
idFromAttributes atts =
  case List.filter (\(name, _) -> name == "id") atts of
    [] -> Nothing
    ((_,id)::_) -> Just id


-- TODO: parse data-click, etc
toAttribute : (AttributeName, AttributeValue) -> Html.Attribute Msg
toAttribute (name, value) =
  case name of
    "data-click" -> 
      Html.onClick (ServerAction value)

    -- TODO, more complex. What does "update" mean in this context? How do we know it's an input field??

    "data-input" -> 
      Html.onInput (ServerUpdate value)

    "data-enter" -> 
      onEnter (ServerAction value)

    "value" -> 
      Html.value value

    "checked" -> 
      Html.checked True

    _ ->
      Html.attribute name value

onEnter : msg -> Attribute msg
onEnter msg =
  (Html.on "keydown"
      (Decode.field "key" Decode.string
          |> Decode.andThen
              (\key ->
                  if key == "Enter" then
                      Decode.succeed msg

                  else
                      Decode.fail "Not the enter key"
              )
      )
  )
