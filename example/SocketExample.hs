{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE NoOverloadedLists #-}
module SocketExample where

import Juniper.Prelude
import Juniper hiding (page)
import Control.Concurrent.STM (newTVar, atomically, TVar)
import Data.Char (isPunctuation, isSpace)
import qualified Data.Map as Map
import Data.ByteString.Lazy (ByteString)
import Data.Monoid (mappend)
import Data.Text (Text)
-- import Control.Monad.Loops (iterateM_)
import Lucid
import Juniper.Params as Params
import qualified Juniper.Web as Web
import Juniper.Encode
import qualified Juniper.Runtime as Runtime hiding (run)
import Control.Concurrent (forkIO, ThreadId, throwTo)
import Control.Concurrent.Async (withAsync, wait, race_)
import Control.Exception (finally, Exception, throw, mask, onException, catch, AsyncException)
import Control.Monad (forM_, forever)
import Control.Concurrent (MVar, newMVar, putMVar, takeMVar)
import qualified Page.Counter as Counter
import qualified Page.Focus as Focus
import qualified Page.Todo as Todo
import Page.Todo (Todo(..))
import GHC.Generics
import Data.Aeson as Aeson (ToJSON, FromJSON(..), decode, Result(..))
import Data.Aeson.Types (Parser)
import qualified Data.Text as T
import qualified Data.Text.IO as T
import Data.UUID as UUID (UUID)
import Data.UUID.V4 as UUID
import System.IO (hSetBuffering, stdout, stdin, BufferMode(NoBuffering))

import qualified Network.WebSockets as WS
import Sockets


import Web.Scotty (scotty)
import Web.Scotty.Trans as Scotty


-- TODO store session information by user id. Embed the user id instead of the state
-- TODO need to make initialization way easier and type safe, right now you have to add it to the routes
  -- and you also need to add it to sockets



startLive :: IO ()
startLive = do
  todos <- atomically $ newTVar [Todo "Test Item" Todo.Errand False]
  concurrent
    (startWebServer todos)
    (startSocket todos)



concurrent :: IO () -> IO () -> IO ()
concurrent act1 act2 = do
  t <- (forkIO act1)
  act2 `catch` (onInterrupt t)
  where
    onInterrupt :: ThreadId -> AsyncException -> IO ()
    onInterrupt t e = do
      throwTo t e
      throw e




startWebServer :: TVar [Todo] -> IO ()
startWebServer todos = do


  let cfg = Render False toDocument

  scotty 3031 $ do
    get "/live.js" $ do
      addHeader "Content-Type" "text/javascript"
      file "dist/main.js"

    -- get "/" $ do
    --   -- handle cfg Counter.page
    --   handle cfg Focus.page
    --   -- html $
    --   --   "This is a test <script src='/live.js'></script>"

    pageRoute cfg "/focus" Focus.page
    pageRoute cfg "/counter" Counter.page
    pageRoute cfg "/todo" (Todo.page todos)
 
    -- page "focus" Focus
    -- it's (model -> Page') that does the trick


-- TODO can we do this with just the constructor?
pageRoute :: (MonadIO m, LiveModel mod, LiveAction act, ToParams prm, ScottyError e) => Render -> RoutePattern -> Page prm mod act (ActionT e m) -> ScottyT e m ()
pageRoute cfg r pg = do
  -- 1. load, then go
  Scotty.get r $ do
    handle cfg pg

    pure ()




toDocument :: Html () -> Html ()
toDocument = simpleDocument "Example" $ do

  -- add stylesheets, etc
  -- link_ [type_ "text/css", rel_ "stylesheet", href_ "/example/example.css"]

  -- In your application, you probably want to embed this javascript via 
  --  > let cfg = Render True toDocument
  -- script_ [type_ "text/javascript", src_ "/build.js"] ("" :: Text)
  -- script_ [type_ "text/javascript", src_ "/run.js"] ("" :: Text)

  -- Custom Javascript should be last
  script_ [type_ "text/javascript", src_ "/live.js"] ("" :: Text)






newtype Message = Message { fromMessage :: ByteString }
  deriving newtype (Eq, WS.WebSocketsData)

instance Show Message where
  show (Message m) = "|" <> cs m <> "|"


data Page'
  = Counter Counter.Model
  | Focus Focus.Model
  | Todos Todo.Model
  deriving (Generic, Show)

instance FromJSON Page' where
  parseJSON v =
        Counter <$> parseJSON v
    <|> Focus <$> parseJSON v
    <|> Todos <$> parseJSON v


-- can you run this in other than IO?
-- not for now
startSocket :: TVar [Todo] -> IO ()
startSocket todos = do
  startLiveView $ \pg ->
    case pg of
      Counter m -> do
        register Counter.page m

      Focus m -> do
        register Focus.page m

      Todos m -> do
        register (Todo.page todos) m



-- we could just have all of this run in their monad?

startLiveView :: forall page m a. (FromJSON page, Show page) => (page -> IO (WS.Connection -> IO ())) -> IO ()
startLiveView pageRun = do

  putStrLn "startLiveView"
  liftIO $ WS.runServer "127.0.0.1" 9160 $ \pending -> do
    putStrLn "Connection!"

    conn <- WS.acceptRequest pending
    page <- identify conn
    run <- pageRun page

    connect run conn `catch` onError

  where
    identify :: WS.Connection -> IO page
    identify conn = do
      msg <- WS.receiveData conn :: IO Message
      case Aeson.decode (fromMessage msg) of
        Nothing -> do
          throw $ NoIdentify msg
        Just p -> do
          putStrLn "Identified"
          print p
          -- WS.sendTextData conn ("Identified" :: Text)
          pure p

    connect :: (WS.Connection -> IO ()) -> WS.Connection -> IO ()
    connect run conn = do
      putStrLn "Connect"
      WS.withPingThread conn 30 (return ()) $ do
        -- finally disconnect $ forever (run conn)
        forever (run conn)

    onError :: SocketError -> IO ()
    onError e = do
      -- putStrLn "ERROR"
      print e

    disconnect :: IO ()
    disconnect = do
      -- perform any cleanup here
      putStrLn "DISCONNECT!"
      pure ()




-- It's all right here, except for the connection
register :: forall action model params. (LiveAction action, Show model) => Page params model action IO -> model -> IO (WS.Connection -> IO ())
register pg initModel = do
  putStrLn "Register"
  st <- liftIO $ newMVar initModel
  putStrLn "Registered"

  pure $ \conn -> do
    putStrLn "Talk"
    msg <- WS.receiveData conn :: IO Message
    print msg

    m <- updateState st msg

    let bs = render m
    WS.sendTextData conn bs

  where

    render :: model -> ByteString
    render m =
      let h = (Runtime.view pg) m
      in Lucid.renderBS h


    updateState :: MVar model -> Message -> IO model
    updateState st msg = do
      modifyMVar st update
      where
        update :: model -> IO model
        update m = do
          case decodeAction (cs $ fromMessage msg) of
            Error _ -> throw $ InvalidAction msg
            Success act -> do
              m' <- (Runtime.update pg) act m
              pure m'



data SocketError
  = NoIdentify Message
  | InvalidAction Message
  deriving (Show, Exception)





-- Taken from Control.Concurrent. Returns the modified variable at the end
modifyMVar :: MVar a -> (a -> IO a) -> IO a
modifyMVar m io =
  mask $ \restore -> do
    a  <- takeMVar m
    a' <- restore (io a) `onException` putMVar m a
    putMVar m a'
    pure a'