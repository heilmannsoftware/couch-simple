{-# LANGUAGE NoImplicitPrelude #-}

{- |

Module      : Database.Couch.Internal
Description : The lowest low-level code for Database.Couch
Copyright   : Copyright (c) 2015, Michael Alan Dorman
License     : MIT
Maintainer  : mdorman@jaunder.io
Stability   : experimental
Portability : POSIX

This module is about things that are at such a low level, they're not
even necessarily really CouchDB-specific.

-}

module Database.Couch.Internal where

import           Control.Monad                 (return, (>>=))
import           Control.Monad.IO.Class        (MonadIO, liftIO)
import           Data.Aeson                    (FromJSON, Value (Null))
import           Data.Aeson.Parser             (json)
import           Data.Attoparsec.ByteString    (IResult (Done, Fail, Partial),
                                                parseWith)
import           Data.Either                   (Either (Right, Left), either)
import           Data.Eq                       ((==))
import           Data.Function                 (flip, ($), (.))
import           Data.Maybe                    (Maybe (Just, Nothing))
import           Data.Monoid                   (mempty)
import           Data.Text                     (pack)
import           Database.Couch.RequestBuilder (RequestBuilder, runBuilder)
import           Database.Couch.ResponseParser (ResponseParser, runParse,
                                                standardParse)
import           Database.Couch.Types          (Context, Error (ParseFail, ParseIncomplete),
                                                Result, ctxCookies, ctxManager)
import           Network.HTTP.Client           (CookieJar, Manager, Request,
                                                equalCookieJar, brRead, method,
                                                responseBody, responseCookieJar,
                                                responseHeaders, responseStatus,
                                                withResponse)
import           Network.HTTP.Types            (ResponseHeaders, Status,
                                                methodHead)

{- | Make an HTTP request returning a JSON value

This is our lowest-level non-streaming routine.  It only handles
performing the request and parsing the result into a JSON value.

It presumes:

 * we will be receiving a deserializable JSON value

 * we do not need to stream out the result (though the input is parsed
incrementally)

The results of parsing the stream will be handed to a routine that
take the output and return the value the user ultimately desires.  We
use "Data.Either" to handle indicating failure and such.

Basing the rest of our library on a function where all dependencies
are explicit should help make sure that other bits remain portable to,
say, streaming interfaces.

-}

rawJsonRequest :: MonadIO m
               => Manager -- ^ The "Network.HTTP.Client.Manager" to use for the request
               -> Request -- ^ The actual request itself
               -> m (Either Error (ResponseHeaders, Status, CookieJar, Value))
rawJsonRequest manager request =
  liftIO (withResponse request manager responseHandler)
  where
    -- Incrementally parse the body, reporting failures.
    responseHandler res = do
      result <- if method request == methodHead
                then return (Done mempty Null)
                else parseParts res
      return $ case result of
        (Done _ ret) -> return (responseHeaders res, responseStatus res, responseCookieJar res, ret)
        (Partial _) -> Left ParseIncomplete
        (Fail _ _ err) -> Left $ ParseFail $ pack err
    parseParts res = do
      let input = brRead (responseBody res)
      initial <- input
      parseWith input json initial

{- | Higher-level wrapper around 'rawJsonRequest'

Building on top of 'rawJsonRequest, this routine is designed to take a
builder for the request and a parser for the result, and use them to
request our transaction.  This makes for a very declarative style when
defining individual endpoints for CouchDB.

In order to support more sophisticated forms of authentication than
'Basic', we do have to examine the cookie jar returned from the
server, and perhaps tell the user that they should replace the cookie
jar in their context with it.

-}

structureRequest :: MonadIO m
                 => RequestBuilder () -- ^ The builder for the HTTP request
                 -> ResponseParser a -- ^ A parser for the data type the requester seeks
                 -> Context -- ^ A context for holding the HTTP manager and the cookie jar
                 -> m (Result a)
structureRequest builder parse context =
  rawJsonRequest manager request >>= parser
  where
    manager =
      ctxManager context
    request =
      runBuilder builder context
    parser =
      return . either Left parseContext
    parseContext (h, s, c, v) =
      runParse parse (Right (h, s, v)) >>= checkContextUpdate c
    checkContextUpdate c a =
      Right (a, if equalCookieJar c (ctxCookies context) then Nothing else Just c)

{- | Make a HTTP request with standard CouchDB semantics

This builds on 'structureRequest', with a standard parser for the
response.

-}

standardRequest :: (FromJSON a, MonadIO m) => RequestBuilder () -> Context -> m (Result a)
standardRequest =
  flip structureRequest standardParse
