{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DerivingStrategies #-}
module Yeti.Events where


import Data.Map as Map (null, empty)
import Yeti.Prelude
import Yeti.Encode
import Yeti.View (TagMod, att)


type Name = Text


newtype FormData = FormData (Map Name Text)
  deriving newtype (Monoid, Semigroup)

instance Show FormData where
  -- if it's empty, display it as _
  show (FormData m) =
    if Map.null m
      then "_"
      else show m

-- We don't need this, it'll be read normally
instance Read FormData where
  readsPrec _ "_" = [(FormData $ Map.empty, "")]
  -- I want to map the fst
  readsPrec n s = fmap fstFormData $ readsPrec n s
    where fstFormData (a, s') = (FormData a, s')




onClick :: (LiveAction action) => action -> TagMod
onClick = on "click"

onInput :: (LiveAction action) => (Text -> action) -> TagMod
onInput = onValue "input"

-- | capture the input event and commit immediately. Should not be used for text inputs
onSelect :: (LiveAction action, Input val) => (val -> action) -> TagMod
onSelect = onValue "input"

onEnter :: (LiveAction action) => action -> TagMod
onEnter = on "enter"



on :: (LiveAction action) => Text -> (action) -> TagMod
on name act = att ("data-on-" <> name) $ fromEncoded $ encodeAction act

onValue :: (LiveAction action, Input val) => Text -> (val -> action) -> TagMod
onValue name con = att ("data-on-" <> name) $ fromEncoded $ encodeAction1 con


