{-# OPTIONS_GHC -F -pgmF=record-dot-preprocessor #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DeriveGeneric #-}
module Page.Counter where

import Sockets
import Prelude
import Juniper
import Control.Monad.IO.Class (MonadIO)
import Lucid (Html, toHtml, Term, term)
import Lucid.Html5

data Model = Model
  { count :: Integer
  } deriving (Show, Generic, LiveModel, ToJSON, FromJSON)

data Action
  = Increment
  | Decrement
  deriving (Show, Generic, LiveAction)


-- just run these in your monad
-- oh, this doesn't want to worry about which monad it is run in
load :: MonadIO m => m Model
load = pure $ Model 0

update :: MonadIO m => Action -> Model -> m Model
update Increment m = pure $ m { count = count m + 1 }
update Decrement m = pure $ m { count = count m - 1 }

view :: Model -> Html ()
view m = section_ [ class_ "page" ] $ do

    div_ [ class_ "section" ] $ do
      button_ [ onClick Decrement] "Decrement"
      button_ [ onClick Increment] "Increment"

    div_ $ do
      input' [type_ "text"] ""

    div_ $ toHtml $ show m.count



-- | @input@ element

input' :: Term arg result => arg -> result
input' = term "input"


page :: MonadIO m => Page () Model Action m
page = simplePage load update view


instance SParams Model () where
  params' = const ()

instance SView Model where
  view' = view

instance MonadIO m => SUpdate Model m where
  type Msg Model = Action
  load' = load
  update' = update

  -- type Msg Model = Action
  -- load' = load
  -- update' = update
  -- view' = view
  -- params' = const ()